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
}

public final class GeminiValidator {
    private let apiKey: String
    private let modelName: String
    private let logger = Logger(subsystem: "com.swingmaster", category: "Gemini")

    public init(apiKey: String, modelName: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.modelName = modelName
    }

    // MARK: - Swing Validation (30 frames)

    public func validateSwing(_ potential: PotentialSwing) async throws -> ValidatedSwing? {
        let images = try await prepareImages(from: potential.frames)
        let prompt = makeValidationPrompt(potential: potential)
        logger.log("[Gemini] Validation frames sent=\(images.count)")
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
        return ValidatedSwing(frames: subframes,
                              type: parsed.swingType,
                              confidence: parsed.confidence,
                              originalTimestamp: potential.timestamp)
    }

    // MARK: - Swing Analysis (5 key frames + metrics)

    public func analyzeSwing(_ swing: ValidatedSwing,
                             metrics: SegmentMetrics) async throws -> AnalysisResult {
        let keyFrames = selectKeyFrames(from: swing.frames)
        let images = try await prepareImages(from: keyFrames)
        let prompt = makeAnalysisPrompt(swing: swing, metrics: metrics)
        logger.log("[Gemini] Analysis frames sent=\(images.count)")
        logger.log("[Gemini] Analysis prompt head=\(self.firstWords(prompt, count: 10), privacy: .public)")
        let response = try await callGeminiAPI(images: images, prompt: prompt)
        logger.log("[Gemini] Analysis response (len=\(response.count)): \(response, privacy: .public)")
        return parseAnalysisResponse(response, swing: swing, metrics: metrics)
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

    private func selectKeyFrames(from frames: [PoseFrame]) -> [PoseFrame] {
        guard !frames.isEmpty else { return [] }
        let count = frames.count
        let indices = [0, count / 4, count / 2, (3 * count) / 4, max(0, count - 1)]
        return indices.map { frames[min($0, count - 1)] }
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
    private func makeValidationPrompt(potential: PotentialSwing) -> String {
        return """
        Analyze these frames showing a potential tennis swing. The peak motion occurs at frame \(potential.peakFrameIndex).
        Return ONLY JSON (no prose, no markdown fences) with exactly these fields and types:
        {
          "is_valid_swing": boolean,
          "swing_type": "forehand" | "backhand",
          "start_frame": number,
          "end_frame": number,
          "confidence": number
        }
        The confidence MUST be a number in [0,1]. If type is uncertain, choose the closest of "forehand" or "backhand".
        """
    }

    private func makeAnalysisPrompt(swing: ValidatedSwing, metrics: SegmentMetrics) -> String {
        return """
        Analyze this validated tennis \(swing.type.rawValue) swing. Metrics: peakAngularVelocity=\(metrics.peakAngularVelocity), peakLinearVelocity=\(metrics.peakLinearVelocity), contactPoint=(\(metrics.contactPoint.x),\(metrics.contactPoint.y)), backswingAngle=\(metrics.backswingAngle), followThroughHeight=\(metrics.followThroughHeight). Return JSON with coaching insights and form_score.
        """
    }

    // Parsing
    private struct ValidationResponse: Decodable {
        let is_valid_swing: Bool
        let swing_type: String
        let start_frame: Int
        let end_frame: Int
        let confidence: FlexibleFloat
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

    private struct AnalysisResponse: Decodable {
        let contact_rating: String
        let contact_adjustment: Float
        let follow_through_rating: String
        let rotation_rating: String
        let form_score: Float
        let insights: [Insight]
        struct Insight: Decodable { let type: String; let message: String; let priority: String }
    }

    private func parseValidationResponse(_ text: String) -> (isValid: Bool, swingType: ShotType, startFrame: Int, endFrame: Int, confidence: Float)? {
        let cleaned = Self.extractJSON(from: text)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(ValidationResponse.self, from: data) else { return nil }
        let type = Self.normalizeShotType(decoded.swing_type)
        return (decoded.is_valid_swing, type, decoded.start_frame, decoded.end_frame, decoded.confidence.value)
    }

    private func parseAnalysisResponse(_ text: String,
                                       swing: ValidatedSwing,
                                       metrics: SegmentMetrics) -> AnalysisResult {
        // Best-effort parsing; if it fails, fallback to a generic insight
        let cleaned = Self.extractJSON(from: text)
        if let data = cleaned.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode(AnalysisResponse.self, from: data)
                let segment = SwingSegment(startTime: swing.originalTimestamp,
                                           endTime: swing.originalTimestamp,
                                           frames: swing.frames)
                let primary = decoded.insights.first?.message ?? "Good swing"
                logger.log("[Gemini] Analysis parsed form_score=\(decoded.form_score, format: .fixed(precision: 2)) insights=\(decoded.insights.count)")
                // Log first insight if available
                if let first = decoded.insights.first {
                    logger.log("[Gemini] First insight: type=\(first.type, privacy: .public) prio=\(first.priority, privacy: .public) msg=\(first.message, privacy: .public)")
                }
                return AnalysisResult(segment: segment, primaryInsight: primary, score: decoded.form_score)
            } catch {
                logger.error("[Gemini] Analysis JSON decode error: \(String(describing: error), privacy: .public)")
            }
        }
        logger.warning("[Gemini] Analysis parse failed; returning fallback insight")
        let segment = SwingSegment(startTime: swing.originalTimestamp,
                                   endTime: swing.originalTimestamp,
                                   frames: swing.frames)
        return AnalysisResult(segment: segment, primaryInsight: "Valid swing detected", score: 7.0)
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


