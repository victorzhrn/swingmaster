//
//  VideoProcessor.swift
//  swingmaster
//
//  Orchestrates full video analysis pipeline with progress reporting.
//

import Foundation
import os
import Vision

@MainActor
public final class VideoProcessor: ObservableObject {
    private let poseProcessor = PoseProcessor()
    private let metricsCalculator = MetricsCalculator()
    private let swingDetector = SwingDetector()
    private let geminiValidator: GeminiValidator
    private let logger = Logger(subsystem: "com.swingmaster", category: "VideoProcessor")

    public enum ProcessingState: Equatable {
        case extractingPoses(progress: Float)
        case calculatingMetrics
        case detectingSwings
        case validatingSwings(current: Int, total: Int)
        case analyzingSwings(current: Int, total: Int)
        case complete
    }

    @Published public private(set) var state: ProcessingState = .extractingPoses(progress: 0)

    public init(geminiAPIKey: String) {
        self.geminiValidator = GeminiValidator(apiKey: geminiAPIKey)
    }

    public func processVideo(_ url: URL) async -> [AnalysisResult] {
        logger.log("[File] Start processing: \(url.lastPathComponent, privacy: .public)")
        // 1) Extract poses
        self.state = .extractingPoses(progress: 0)
        let poseFrames = await poseProcessor.processVideoFile(url, targetFPS: 10.0) { [weak self] p in
            Task { @MainActor in self?.state = .extractingPoses(progress: p) }
        }
        logPoseExtractionSummary(frames: poseFrames, context: "[File]")

        // 2) Calculate metrics
        self.state = .calculatingMetrics
        let metrics = metricsCalculator.calculateMetrics(for: poseFrames)
        logMetricsSummary(frames: poseFrames, metrics: metrics, context: "[File]")

        // 3) Detect potential swings
        self.state = .detectingSwings
        let potentialSwings = swingDetector.detectPotentialSwings(frames: poseFrames, metrics: metrics)
        logger.log("[File] Detected \(potentialSwings.count) potential swing(s)")
        for (idx, c) in potentialSwings.enumerated() {
            logger.log("[File] Candidate #\(idx + 1) frames=\(c.frames.count) peakVelocity=\(c.peakVelocity, format: .fixed(precision: 3)) ts=\(c.timestamp, privacy: .public)")
        }

        // 4) Validate each swing
        var validated: [ValidatedSwing] = []
        if !potentialSwings.isEmpty {
            for (idx, candidate) in potentialSwings.enumerated() {
                self.state = .validatingSwings(current: idx + 1, total: potentialSwings.count)
                logger.log("[File] Sending candidate #\(idx + 1)/\(potentialSwings.count) to validator…")
                if let vs = try? await geminiValidator.validateSwing(candidate) {
                    validated.append(vs)
                    logger.log("[File] Validation OK: type=\(vs.type.rawValue, privacy: .public) confidence=\(vs.confidence, format: .fixed(precision: 2)) frames=\(vs.frames.count)")
                } else {
                    logger.warning("[File] Validation returned nil for candidate #\(idx + 1)")
                }
            }
        }

        // 5) Analyze validated swings
        var results: [AnalysisResult] = []
        if !validated.isEmpty {
            for (idx, swing) in validated.enumerated() {
                self.state = .analyzingSwings(current: idx + 1, total: validated.count)
                let segmentMetrics = metricsCalculator.calculateSegmentMetrics(for: swing.frames)
                if let analysis = try? await geminiValidator.analyzeSwing(swing, metrics: segmentMetrics) {
                    results.append(analysis)
                    logger.log("[File] Analysis #\(idx + 1) score=\(analysis.score, format: .fixed(precision: 2)) insightLen=\(analysis.primaryInsight.count)")
                } else {
                    logger.warning("[File] Analysis failed for validated swing #\(idx + 1)")
                }
            }
        }

        self.state = .complete
        logger.log("[File] Complete. Results=\(results.count)")
        return results
    }

    public func processLiveSession(_ frames: [PoseFrame]) async -> [AnalysisResult] {
        logger.log("[Live] Start processing \(frames.count) frames")
        // Live variant using already collected frames
        logPoseExtractionSummary(frames: frames, context: "[Live]")
        self.state = .calculatingMetrics
        let metrics = metricsCalculator.calculateMetrics(for: frames)
        logMetricsSummary(frames: frames, metrics: metrics, context: "[Live]")
        self.state = .detectingSwings
        let potentialSwings = swingDetector.detectPotentialSwings(frames: frames, metrics: metrics)
        logger.log("[Live] Detected \(potentialSwings.count) potential swing(s)")

        var validated: [ValidatedSwing] = []
        for (idx, candidate) in potentialSwings.enumerated() {
            self.state = .validatingSwings(current: idx + 1, total: potentialSwings.count)
            logger.log("[Live] Sending candidate #\(idx + 1)/\(potentialSwings.count) to validator…")
            if let vs = try? await geminiValidator.validateSwing(candidate) {
                validated.append(vs)
                logger.log("[Live] Validation OK: type=\(vs.type.rawValue, privacy: .public) confidence=\(vs.confidence, format: .fixed(precision: 2)) frames=\(vs.frames.count)")
            } else {
                logger.warning("[Live] Validation returned nil for candidate #\(idx + 1)")
            }
        }

        var results: [AnalysisResult] = []
        for (idx, swing) in validated.enumerated() {
            self.state = .analyzingSwings(current: idx + 1, total: validated.count)
            let segmentMetrics = metricsCalculator.calculateSegmentMetrics(for: swing.frames)
            if let analysis = try? await geminiValidator.analyzeSwing(swing, metrics: segmentMetrics) {
                results.append(analysis)
                logger.log("[Live] Analysis #\(idx + 1) score=\(analysis.score, format: .fixed(precision: 2)) insightLen=\(analysis.primaryInsight.count)")
            } else {
                logger.warning("[Live] Analysis failed for validated swing #\(idx + 1)")
            }
        }

        self.state = .complete
        logger.log("[Live] Complete. Results=\(results.count)")
        return results
    }

    // MARK: - Debug helpers

    private func logPoseExtractionSummary(frames: [PoseFrame], context: String) {
        logger.log("\(context, privacy: .public) Pose frames=\(frames.count)")
        guard let first = frames.first else { return }
        let jointCountFirst = first.joints.count
        let hasRightWristFirst = first.joints[.rightWrist] != nil
        let hasLeftWristFirst = first.joints[.leftWrist] != nil
        let rightWristPresence = presenceRate(frames: frames, joint: .rightWrist)
        logger.log("\(context, privacy: .public) First frame joints=\(jointCountFirst) rightWrist=\(hasRightWristFirst) leftWrist=\(hasLeftWristFirst)")
        let presencePct = rightWristPresence * 100.0
        logger.log("\(context, privacy: .public) rightWrist presence=\(presencePct, format: .fixed(precision: 1))%")
    }

    private func logMetricsSummary(frames: [PoseFrame], metrics: FrameMetrics, context: String) {
        let peakAngular = metrics.angularVelocities.max() ?? 0
        let peakLinear = metrics.linearVelocities.max() ?? 0
        logger.log("\(context, privacy: .public) Metrics peakAngular=\(peakAngular, format: .fixed(precision: 3)) rad/s peakLinear=\(peakLinear, format: .fixed(precision: 3))")
        // Right wrist height stats (raw from frames)
        let rightHeights: [Double] = frames.compactMap { f in
            if let y = f.joints[.rightWrist]?.y { return Double(y) }
            return nil
        }
        if !rightHeights.isEmpty {
            let sum = rightHeights.reduce(0, +)
            let avg = sum / Double(rightHeights.count)
            let maxH = rightHeights.max() ?? 0
            logger.log("\(context, privacy: .public) rightWrist height avg=\(avg, format: .fixed(precision: 3)) max=\(maxH, format: .fixed(precision: 3))")
        } else {
            logger.warning("\(context, privacy: .public) rightWrist height unavailable (no detections)")
        }
    }

    private func presenceRate(frames: [PoseFrame], joint: VNHumanBodyPoseObservation.JointName) -> Double {
        guard !frames.isEmpty else { return 0 }
        var countPresent = 0
        for f in frames { if f.joints[joint] != nil { countPresent += 1 } }
        return Double(countPresent) / Double(frames.count)
    }
}


