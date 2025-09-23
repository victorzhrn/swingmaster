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

public struct ValidatedSwing: Sendable, Codable {
    public let frames: [PoseFrame]
    public let type: ShotType
    public let confidence: Float
    public let originalTimestamp: TimeInterval
    public let keyFrameIndices: KeyFrameIndices
    public let keyFrameTimes: KeyFrameTimes
}

public struct KeyFrameIndices: Sendable, Codable {
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

    // MARK: - Swing Validation (1 image + CSV for all frames)

    public func validateSwing(_ potential: PotentialSwing,
                              objectFrames: [ObjectDetectionFrame] = []) async throws -> ValidatedSwing? {
        logger.log("[Gemini] Start validation. frames=\(potential.frames.count) peakIndex=\(potential.peakFrameIndex) objFrames=\(objectFrames.count)")
        // Render single peak frame image
        let peakFrame = potential.frames[potential.peakFrameIndex]
        logger.log("[Gemini] Rendering peak frame image… ts=\(peakFrame.timestamp, privacy: .public)")
        let peakImage = try await renderSingleFrame(peakFrame)
        logger.log("[Gemini] Peak image prepared (base64 length=\(peakImage.count))")

        // Extract metrics and convert to CSV
        logger.log("[Gemini] Extracting per-frame metrics…")
        let metrics = extractAllFrameMetrics(potential, objectFrames: objectFrames)
        logger.log("[Gemini] Metrics extracted rows=\(metrics.count)")
        logger.log("[Gemini] Building CSV…")
        let csv = metricsToCSV(metrics)
        logger.log("[Gemini] CSV built chars=\(csv.count)")
        let prompt = makeCSVPrompt(csv: csv, peakIndex: potential.peakFrameIndex)
        let systemPrompt = makeSystemPrompt()
        logger.log("[Gemini] Validation with CSV rows=\(metrics.count) and 1 image")
        logger.log("[Gemini] Prompt head=\(self.firstWords(prompt, count: 12), privacy: .public)")
        logger.log("[Gemini] Calling API… model=\(self.modelName, privacy: .public)")
        let response: String
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            response = try await callGeminiAPI(images: [peakImage], prompt: prompt, systemPrompt: systemPrompt)
            let dtMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            logger.log("[Gemini] API call completed in \(dtMs) ms")
        } catch {
            let dtMs = Int((CFAbsoluteTimeGetCurrent()) * 1000) // coarse timing if needed
            let nsErr = error as NSError
            logger.error("[Gemini] API call failed in ~\(dtMs) ms: code=\(nsErr.code) domain=\(nsErr.domain, privacy: .public) desc=\(nsErr.localizedDescription, privacy: .public)")
            return nil
        }
        logger.log("[Gemini] API response received len=\(response.count)")
        logger.log("[Gemini] Validation response (len=\(response.count)): \(response, privacy: .public)")

        logger.log("[Gemini] Parsing response JSON…")
        guard let parsed = parseValidationResponse(response), parsed.isValid else {
            logger.warning("[Gemini] Validation parse failed or is_valid=false")
            return nil
        }

        logger.log("[Gemini] Parsed: type=\(parsed.swingType.rawValue, privacy: .public) conf=\(parsed.confidence, format: .fixed(precision: 2)) start=\(parsed.startFrame) end=\(parsed.endFrame)")
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
        logger.log("[Gemini] Local key frames (prep,back,contact,follow,recover)=\(localKF.preparation),\(localKF.backswing),\(localKF.contact),\(localKF.followThrough),\(localKF.recovery)")
        // Compute absolute timestamps for key frames from local indices
        let safeIndex: (Int) -> Int = { i in max(0, min(i, subframes.count - 1)) }
        let times = KeyFrameTimes(
            preparation: subframes[safeIndex(localKF.preparation)].timestamp,
            backswing: subframes[safeIndex(localKF.backswing)].timestamp,
            contact: subframes[safeIndex(localKF.contact)].timestamp,
            followThrough: subframes[safeIndex(localKF.followThrough)].timestamp,
            recovery: subframes[safeIndex(localKF.recovery)].timestamp
        )
        return ValidatedSwing(frames: subframes,
                              type: parsed.swingType,
                              confidence: parsed.confidence,
                              originalTimestamp: potential.timestamp,
                              keyFrameIndices: localKF,
                              keyFrameTimes: times)
    }


    // MARK: - Single-frame render
    private func renderSingleFrame(_ frame: PoseFrame) async throws -> String {
        if let data = Self.renderSkeletonPNG(frame: frame, width: 480, height: 480) {
            return data.base64EncodedString()
        }
        return ""
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
    private func callGeminiAPI(images: [String], prompt: String, systemPrompt: String? = nil) async throws -> String {
        struct Part: Encodable { let text: String?; let inline_data: InlineData? }
        struct InlineData: Encodable { let mime_type: String; let data: String }
        struct Content: Encodable { let parts: [Part] }
        struct RequestBody: Encodable {
            let contents: [Content]
            let generationConfig: GenerationConfig
            let systemInstruction: Content?
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

        var parts: [Part] = []
        parts.append(Part(text: prompt, inline_data: nil))
        for img in images {
            if img.isEmpty { continue }
            parts.append(Part(text: nil, inline_data: InlineData(mime_type: "image/png", data: img)))
        }

        let sysContent = (systemPrompt?.isEmpty == false) ? Content(parts: [Part(text: systemPrompt!, inline_data: nil)]) : nil
        let body = RequestBody(
            contents: [Content(parts: parts)],
            generationConfig: GenerationConfig(temperature: 0.2, topK: 40, topP: 0.95, maxOutputTokens: 16000),
            systemInstruction: sysContent
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(body)

        // Debug log sanitized request
        let imageSummaries: [String] = images.enumerated().map { idx, img in "image[\(idx)]: png, base64Len=\(img.count)" }
        // (debug logs removed)

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

    // Prompt construction for CSV-based validation
    private func makeCSVPrompt(csv: String, peakIndex: Int) -> String {
        return """
        The attached image is the peak-velocity frame. Below is the CSV time series for all frames.

        CSV columns:
        wristVel,wristX,wristY,elbowAng,hipRot,racketX,racketY,racketDist

        CSV data:
        \(csv)
        """
    }

    private func makeSystemPrompt() -> String {
        return """
        ROLE: Expert tennis swing analyst and strict JSON generator.

        INPUTS:
        - One peak-velocity frame image
        - CSV for all frames with columns: wristVel,wristX,wristY,elbowAng,hipRot,racketX,racketY,racketDist

        STRATEGY:
        1) Use CSV patterns to determine swing type and key moments.
        2) Cross-check with the image for plausibility at peak.
        3) When racket fields are empty, proceed using body metrics only.
        4) Use these cues:
           - preparation: low wristVel, small racketDist
           - backswing: wristX/racketX at extreme opposite to follow-through
           - contact: peak wristVel, large racketDist (~0.7+), wristY/racketY ~0.4-0.6
           - follow_through: wristX/racketX beyond contact, racketDist decreasing
           - recovery: velocities declining, return toward center

        OUTPUT FORMAT (JSON only, no prose):
        {
          "is_valid_swing": boolean,
          "swing_type": "forehand" | "backhand",
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

// MARK: - CSV metrics extraction (fileprivate helpers)
fileprivate struct ValidationFrameMetric {
    let index: Int
    let timestamp: Double
    let wristVelocity: Double
    let wristRelativeX: Double
    let wristHeight: Double
    let elbowAngle: Double
    let hipRotation: Double
    let racketX: Double?
    let racketY: Double?
    let racketWristDist: Double?
}

fileprivate extension GeminiValidator {
    func metricsToCSV(_ metrics: [ValidationFrameMetric]) -> String {
        var csv = "idx,time,wristVel,wristX,wristY,elbowAng,hipRot,racketX,racketY,racketDist\n"
        for m in metrics {
            var row: [String] = []
            row.append(String(m.index))
            row.append(String(format: "%.3f", m.timestamp))
            row.append(String(format: "%.2f", m.wristVelocity))
            row.append(String(format: "%.2f", m.wristRelativeX))
            row.append(String(format: "%.2f", m.wristHeight))
            row.append(String(format: "%.2f", m.elbowAngle))
            row.append(String(format: "%.2f", m.hipRotation))
            row.append(m.racketX.map { String(format: "%.2f", $0) } ?? "")
            row.append(m.racketY.map { String(format: "%.2f", $0) } ?? "")
            row.append(m.racketWristDist.map { String(format: "%.2f", $0) } ?? "")
            csv += row.joined(separator: ",") + "\n"
        }
        return csv
    }

    func extractAllFrameMetrics(_ potential: PotentialSwing,
                                objectFrames: [ObjectDetectionFrame]) -> [ValidationFrameMetric] {
        return potential.frames.enumerated().map { index, frame in
            let rightWrist = frame.joints[.rightWrist] ?? CGPoint(x: 0.5, y: 0.5)
            let rightElbow = frame.joints[.rightElbow] ?? CGPoint(x: 0.55, y: 0.55)
            let rightShoulder = frame.joints[.rightShoulder] ?? CGPoint(x: 0.6, y: 0.6)
            let leftHip = frame.joints[.leftHip] ?? CGPoint(x: 0.4, y: 0.4)
            let rightHip = frame.joints[.rightHip] ?? CGPoint(x: 0.6, y: 0.4)

            let centerX = (leftHip.x + rightHip.x) / 2
            let objectFrame = findClosestObjectFrame(timestamp: frame.timestamp, in: objectFrames)

            var racketX: Double? = nil
            var racketY: Double? = nil
            var racketWristDist: Double? = nil
            if let racket = objectFrame?.racket {
                let racketCenter = CGPoint(x: racket.boundingBox.midX, y: racket.boundingBox.midY)
                let relX = Double((racketCenter.x - centerX) * 2.0)
                racketX = max(-1.0, min(1.0, relX))
                racketY = Double(racketCenter.y)
                let dist = Double(sqrt(pow(racketCenter.x - rightWrist.x, 2) + pow(racketCenter.y - rightWrist.y, 2)))
                racketWristDist = dist
            }

            let hipRot = atan2(rightHip.y - leftHip.y, rightHip.x - leftHip.x)
            let elbowAng = calculateAngleBetweenPoints(p1: rightShoulder, p2: rightElbow, p3: rightWrist)
            let wristRelX = max(-1.0, min(1.0, Double((rightWrist.x - centerX) * 2.0)))

            let velocity = index < potential.angularVelocities.count ? Double(potential.angularVelocities[index]) : 0.0

            return ValidationFrameMetric(
                index: index,
                timestamp: frame.timestamp,
                wristVelocity: velocity,
                wristRelativeX: wristRelX,
                wristHeight: Double(rightWrist.y),
                elbowAngle: elbowAng,
                hipRotation: Double(hipRot),
                racketX: racketX,
                racketY: racketY,
                racketWristDist: racketWristDist
            )
        }
    }

    func findClosestObjectFrame(timestamp: TimeInterval,
                                in frames: [ObjectDetectionFrame]) -> ObjectDetectionFrame? {
        return frames.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) })
    }

    func calculateAngleBetweenPoints(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> Double {
        let v1 = CGPoint(x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = CGPoint(x: p3.x - p2.x, y: p3.y - p2.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let det = v1.x * v2.y - v1.y * v2.x
        return abs(atan2(det, dot))
    }
}



