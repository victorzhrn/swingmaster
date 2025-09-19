//
//  GeminiValidator.swift
//  swingmaster
//
//  Validates potential swings using an external multimodal model and
//  produces coaching analysis. This is a scaffold with replaceable API calls.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import os

public struct ValidatedSwing: Sendable {
    public let frames: [PoseFrame]
    public let type: ShotType
    public let confidence: Float
    public let originalTimestamp: TimeInterval
    public let keyFrameIndices: KeyFrameIndices
}

public struct KeyFrameIndices: Sendable {
    public let preparation: Int
    public let backswing: Int
    public let contact: Int
    public let followThrough: Int
    public let recovery: Int
}

public final class GeminiValidator {
    private let apiKey: String
    private let modelName: String
    private let logger = Logger(subsystem: "com.swingmaster", category: "Gemini")

    public init(apiKey: String, modelName: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.modelName = modelName
    }

    // MARK: - Swing Validation (8 sampled frames from 30)

    public func validateSwing(_ potential: PotentialSwing) async throws -> ValidatedSwing? {
        // Sample approximately 8 frames from the candidate sequence (dynamic length)
        // Weight sampling toward the peak for better accuracy
        let sampledFrames = sampleFramesForValidation(potential.frames, peakIndex: potential.peakFrameIndex, targetCount: 8)
        let images = try await prepareImages(from: sampledFrames.map { $0.frame })
        let prompt = makeValidationPrompt(potential: potential, sampledFrameIndices: sampledFrames.map { $0.originalIndex })
        logger.log("[Gemini] Validation frames sent=\(images.count) (sampled from \(potential.frames.count))")
        logger.log("[Gemini] Validation prompt head=\(self.firstWords(prompt, count: 10), privacy: .public)")
        let response = try await callGeminiAPI(images: images, prompt: prompt)
        logger.log("[Gemini] Validation response (len=\(response.count)): \(response, privacy: .public)")

        guard let parsed = parseValidationResponse(response), parsed.isValid else {
            logger.warning("[Gemini] Validation parse failed or is_valid=false")
            return nil
        }

        let startIdx = max(0, min(parsed.startFrame, potential.frames.count - 1))
        let endIdx = max(startIdx, min(parsed.endFrame, potential.frames.count - 1))
        let subframes = Array(potential.frames[startIdx...endIdx])
        // Translate key frame indices to local subframe space and clamp
        let clamp: (Int) -> Int = { i in
            return max(0, min(i - startIdx, subframes.count - 1))
        }
        let localKF = KeyFrameIndices(
            preparation: clamp(parsed.keyFrames.preparation),
            backswing: clamp(parsed.keyFrames.backswing),
            contact: clamp(parsed.keyFrames.contact),
            followThrough: clamp(parsed.keyFrames.follow_through),
            recovery: clamp(parsed.keyFrames.recovery)
        )
        return ValidatedSwing(frames: subframes,
                              type: parsed.swingType,
                              confidence: parsed.confidence,
                              originalTimestamp: potential.timestamp,
                              keyFrameIndices: localKF)
    }


    // MARK: - Frame Sampling
    
    private func sampleFramesForValidation(_ frames: [PoseFrame], peakIndex: Int, targetCount: Int) -> [(originalIndex: Int, frame: PoseFrame)] {
        guard frames.count > targetCount else {
            // If we have fewer frames than target, return all
            return frames.enumerated().map { ($0.offset, $0.element) }
        }
        
        var selectedIndices: Set<Int> = []
        
        // Always include first and last frames
        selectedIndices.insert(0)
        selectedIndices.insert(frames.count - 1)
        
        // Always include peak frame
        selectedIndices.insert(peakIndex)
        
        // Add frames around the peak (higher density near peak)
        let nearPeakOffsets = [-6, -3, 3, 6]
        for offset in nearPeakOffsets {
            let idx = peakIndex + offset
            if idx >= 0 && idx < frames.count {
                selectedIndices.insert(idx)
            }
        }
        
        // If we need more frames, add evenly distributed ones
        while selectedIndices.count < targetCount && selectedIndices.count < frames.count {
            let step = frames.count / targetCount
            for i in stride(from: 0, to: frames.count, by: step) {
                selectedIndices.insert(i)
                if selectedIndices.count >= targetCount { break }
            }
        }
        
        // Convert to sorted array and return with original indices
        let sortedIndices = selectedIndices.sorted()
        return sortedIndices.prefix(targetCount).map { idx in
            (originalIndex: idx, frame: frames[idx])
        }
    }

    // MARK: - Helper Methods (Scaffold)

    private func prepareImages(from frames: [PoseFrame]) async throws -> [String] {
        // Render simple skeleton images from PoseFrame using CoreGraphics, 480x480 PNGs
        let width: Int = 480
        let height: Int = 480
        var encoded: [String] = []
        encoded.reserveCapacity(frames.count)

        for frame in frames {
            if let data = Self.renderSkeletonPNG(frame: frame, width: width, height: height) {
                encoded.append(data.base64EncodedString())
            } else {
                // If rendering fails, still append an empty placeholder to preserve alignment
                encoded.append("")
            }
        }
        return encoded
    }

    private func extractKeyFrames(_ swing: ValidatedSwing) -> [(type: KeyFrameType, index: Int, frame: PoseFrame)] {
        let f = swing.frames
        guard !f.isEmpty else { return [] }
        let k = swing.keyFrameIndices
        let safe: (Int) -> Int = { i in max(0, min(i, f.count - 1)) }
        return [
            (.preparation, safe(k.preparation), f[safe(k.preparation)]),
            (.backswing, safe(k.backswing), f[safe(k.backswing)]),
            (.contact, safe(k.contact), f[safe(k.contact)]),
            (.followThrough, safe(k.followThrough), f[safe(k.followThrough)]),
            (.recovery, safe(k.recovery), f[safe(k.recovery)])
        ]
    }

    // Networking: call Gemini generateContent with text + inline image data
    private func callGeminiAPI(images: [String], prompt: String) async throws -> String {
        struct Part: Encodable { let text: String?; let inline_data: InlineData? }
        struct InlineData: Encodable { let mime_type: String; let data: String }
        struct Content: Encodable { let parts: [Part] }
        struct RequestBody: Encodable {
            let contents: [Content]
            let generationConfig: GenerationConfig
        }
        struct GenerationConfig: Encodable {
            let temperature: Double
            let topK: Int
            let topP: Double
            let maxOutputTokens: Int
        }
        struct ResponseBody: Decodable {
            struct Candidate: Decodable {
                struct RContent: Decodable {
                    struct RPart: Decodable { let text: String? }
                    let parts: [RPart]?
                }
                let content: RContent?
            }
            let candidates: [Candidate]?
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var parts: [Part] = [Part(text: prompt, inline_data: nil)]
        for img in images {
            if img.isEmpty { continue }
            parts.append(Part(text: nil, inline_data: InlineData(mime_type: "image/png", data: img)))
        }

        let body = RequestBody(
            contents: [Content(parts: parts)],
            generationConfig: GenerationConfig(temperature: 0.2, topK: 40, topP: 0.95, maxOutputTokens: 16000)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            logger.error("[Gemini] HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1) body=\(msg, privacy: .public)")
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?.compactMap { $0.text }.joined(separator: "\n")
        if let text = text, !text.isEmpty { return text }
        // Fallback: return raw JSON if no text part
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Prompt construction
    private func makeValidationPrompt(potential: PotentialSwing, sampledFrameIndices: [Int]) -> String {
        let frameDescription = sampledFrameIndices.enumerated().map { idx, originalIdx in
            "Frame \(idx): original frame \(originalIdx)"
        }.joined(separator: ", ")
        
        return """
        Analyze these \(sampledFrameIndices.count) sampled frames from a sequence of \(potential.frames.count) frames showing a potential tennis swing.
        These frames are sampled from the original sequence at indices: \(sampledFrameIndices.map(String.init).joined(separator: ", "))
        The peak motion occurs at original frame \(potential.peakFrameIndex).

        Tasks:
        1. Confirm if this is a valid tennis swing
        2. Identify exact start/end frames (use ORIGINAL frame numbers from 0 to \(potential.frames.count - 1))
        3. Classify swing type by observing body rotation and hand grip (assume right-handed player):
           
           FOREHAND vs BACKHAND Detection:
           - FOREHAND: 
             * Body rotates COUNTER-CLOCKWISE (when viewed from above)
             * Torso turns from right to left during swing
             * ALWAYS uses ONE hand on racket
             * Right shoulder moves forward through contact
             * Swing path goes from player's right side to left side
           
           - BACKHAND:
             * Body rotates CLOCKWISE (when viewed from above)  
             * Torso turns from left to right during swing
             * USUALLY uses TWO hands on racket (but can be one-handed)
             * Left shoulder moves forward through contact
             * Swing path goes from player's left side to right side
        
        4. Identify the ORIGINAL frame index for each key moment:
           - Preparation stance
           - Peak of backswing
           - Ball contact
           - Maximum follow-through
           - Recovery position

        Important: All frame numbers in your response should refer to the ORIGINAL sequence of \(potential.frames.count) frames (0..\(potential.frames.count - 1)), not the sampled frames.

        Return ONLY JSON (no prose, no markdown fences):
        {
            "is_valid_swing": boolean,
            "swing_type": "forehand" | "backhand" | "unknown",
            "start_frame": number,
            "end_frame": number,
            "confidence": number,
            "key_frames": {
                "preparation": number,
                "backswing": number,
                "contact": number,
                "follow_through": number,
                "recovery": number
            }
        }
        """
    }


    // Parsing
    private struct ValidationResponse: Decodable {
        struct KeyFrames: Decodable {
            let preparation: Int
            let backswing: Int
            let contact: Int
            let follow_through: Int
            let recovery: Int
        }
        let is_valid_swing: Bool
        let swing_type: String
        let start_frame: Int
        let end_frame: Int
        let confidence: FlexibleFloat
        let key_frames: KeyFrames
    }

    private struct FlexibleFloat: Decodable {
        let value: Float
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let num = try? container.decode(Float.self) {
                value = num
            } else if let str = try? container.decode(String.self) {
                value = Float(str) ?? 0.0
            } else {
                value = 0.0
            }
        }
    }


    private func parseValidationResponse(_ text: String) -> (isValid: Bool, swingType: ShotType, startFrame: Int, endFrame: Int, confidence: Float, keyFrames: ValidationResponse.KeyFrames)? {
        let cleaned = Self.extractJSON(from: text)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(ValidationResponse.self, from: data) else { return nil }
        let type = Self.normalizeShotType(decoded.swing_type)
        return (decoded.is_valid_swing, type, decoded.start_frame, decoded.end_frame, decoded.confidence.value, decoded.key_frames)
    }


    // MARK: - Utils

    private func firstWords(_ text: String, count: Int) -> String {
        let comps = text.split { $0.isWhitespace }
        if comps.isEmpty { return "" }
        let prefix = comps.prefix(count)
        return prefix.joined(separator: " ")
    }

    // MARK: - Image Rendering

    private static func extractJSON(from text: String) -> String {
        // Strip markdown fences if present and trim
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // Remove first fence line
            if let range = s.range(of: "\n") { s = String(s[range.upperBound...]) }
            // Remove optional language tag line if present
            if s.hasPrefix("json\n") { s = String(s.dropFirst(5)) }
            // Remove trailing fence
            if let lastFence = s.range(of: "```", options: .backwards) {
                s = String(s[..<lastFence.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeShotType(_ raw: String) -> ShotType {
        let lower = raw.lowercased()
        if lower.contains("forehand") { return .forehand }
        if lower.contains("backhand") { return .backhand }
        return ShotType(rawValue: lower) ?? .unknown
    }

    // MARK: - Text Shortening

    private static func shorten(items: [String], maxCount: Int, maxChars: Int) -> [String] {
        let trimmed = items.prefix(maxCount).map { shorten(text: $0, maxChars: maxChars) }
        return Array(trimmed)
    }

    private static func shorten(text: String, maxChars: Int) -> String {
        let squashed = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if squashed.count <= maxChars { return squashed }
        let idx = squashed.index(squashed.startIndex, offsetBy: maxChars)
        var shortened = String(squashed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !shortened.hasSuffix(".") { shortened += "…" }
        return shortened
    }

    private static func renderSkeletonPNG(frame: PoseFrame, width: Int, height: Int) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else { return nil }

        // Background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw bones
        ctx.setLineWidth(4)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for (a, b) in Self.bonePairs {
            guard let pa = frame.joints[a], let pb = frame.joints[b] else { continue }
            let p1 = convert(point: pa, width: width, height: height)
            let p2 = convert(point: pb, width: width, height: height)
            ctx.beginPath()
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
        }

        // Draw joints
        for (name, p) in frame.joints {
            let conf = frame.confidences[name] ?? 0
            let color: CGColor
            if conf > 0.8 { color = CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1) }
            else if conf > 0.5 { color = CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1) }
            else { color = CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1) }
            let pt = convert(point: p, width: width, height: height)
            ctx.setFillColor(color)
            let r: CGFloat = 3
            ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
        }

        guard let img = ctx.makeImage() else { return nil }

        let mutableData = NSMutableData()
        let pngType = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(mutableData, pngType, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    private static func convert(point: CGPoint, width: Int, height: Int) -> CGPoint {
        let x = point.x * CGFloat(width)
        let y = (1.0 - point.y) * CGFloat(height)
        return CGPoint(x: x, y: y)
    }

    private static let bonePairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .root),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .neck), (.rightShoulder, .neck),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftHip, .root), (.rightHip, .root)
    ]
}



