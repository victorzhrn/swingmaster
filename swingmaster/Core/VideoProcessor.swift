//
//  VideoProcessor.swift
//  swingmaster
//
//  Orchestrates full video analysis pipeline with progress reporting.
//

import Foundation
import os
import Vision
import AVFoundation

@MainActor
public final class VideoProcessor: ObservableObject {
    private let poseProcessor = PoseProcessor()
    private let objectDetector = TennisObjectDetector()
    private let contactDetector = ContactPointDetector()
    private let metricsCalculator = MetricsCalculator()
    private let swingDetector = SwingDetector()
    private let geminiValidator: GeminiValidator
    private let logger = Logger(subsystem: "com.swingmaster", category: "VideoProcessor")

    public enum ProcessingState: Equatable {
        case extractingPoses(progress: Float)
        case calculatingMetrics
        case detectingSwings
        case validatingSwings(current: Int, total: Int)
        case complete
    }

    @Published public private(set) var state: ProcessingState = .extractingPoses(progress: 0)

    public init(geminiAPIKey: String) {
        self.geminiValidator = GeminiValidator(apiKey: geminiAPIKey)
    }

    private func processVideoWithObjects(_ url: URL) async -> ([PoseFrame], [ObjectDetectionFrame]) {
        // Read the video's native FPS and use it for pose extraction
        let videoFPS = getVideoFPS(from: url) ?? 10.0
        logger.log("[File] Using video FPS: \(videoFPS, format: .fixed(precision: 1))")
        
        // Extract poses first
        let poseFrames = await poseProcessor.processVideoFile(url, targetFPS: videoFPS) { [weak self] p in
            Task { @MainActor in self?.state = .extractingPoses(progress: p * 0.5) } // First 50% of progress
        }

        // Extract object detection for the entire video duration
        guard !poseFrames.isEmpty else {
            return (poseFrames, [])
        }
        
        let startTime = poseFrames.first?.timestamp ?? 0
        let endTime = poseFrames.last?.timestamp ?? 0
        
        // Update state for object detection phase
        await MainActor.run { self.state = .extractingPoses(progress: 0.5) }
        
        // Run object detection on the full video timespan
        let objectFrames = await objectDetector.detectObjects(
            in: url,
            start: startTime,
            end: endTime,
            orientation: .right,
            confidenceThreshold: 0.3
        )
        
        // Update progress to complete
        await MainActor.run { self.state = .extractingPoses(progress: 1.0) }
        
        logger.log("[File] Extracted \(poseFrames.count) pose frames and \(objectFrames.count) object frames")
        return (poseFrames, objectFrames)
    }

    // Helper to extract padded segment data
    private func extractPaddedSegmentData(
        swing: ValidatedSwing,
        allPoseFrames: [PoseFrame],
        allObjectFrames: [ObjectDetectionFrame],
        paddingSeconds: Double = 0.5
    ) -> (poseFrames: [PoseFrame], objectFrames: [ObjectDetectionFrame]) {
        let swingStart = swing.frames.first?.timestamp ?? 0
        let swingEnd = swing.frames.last?.timestamp ?? 0
        
        // Add padding to capture full motion
        let paddedStart = swingStart - paddingSeconds
        let paddedEnd = swingEnd + paddingSeconds
        
        // Filter frames within padded window
        let relevantPoses = allPoseFrames.filter { 
            $0.timestamp >= paddedStart && $0.timestamp <= paddedEnd 
        }
        
        let relevantObjects = allObjectFrames.filter { 
            $0.timestamp >= paddedStart && $0.timestamp <= paddedEnd 
        }
        
        return (relevantPoses, relevantObjects)
    }
    
    public func processVideo(_ url: URL) async -> [AnalysisResult] {
        logger.log("[File] Start processing: \(url.lastPathComponent, privacy: .public)")
        // 1) Extract poses AND objects
        self.state = .extractingPoses(progress: 0)
        
        let (poseFrames, objectFrames) = await processVideoWithObjects(url)
        logPoseExtractionSummary(frames: poseFrames, context: "[File]")

        // 2) Calculate metrics with object data
        self.state = .calculatingMetrics
        let metrics = metricsCalculator.calculateMetrics(for: poseFrames)
        logMetricsSummary(frames: poseFrames, metrics: metrics, context: "[File]")

        // 3) Detect potential swings
        self.state = .detectingSwings
        let potentialSwings = swingDetector.detectPotentialSwings(frames: poseFrames, metrics: metrics)
        logger.log("[File] Detected \(potentialSwings.count) potential swing(s)")
        for (idx, c) in potentialSwings.enumerated() {
            let startTS = c.frames.first?.timestamp ?? 0
            let endTS = c.frames.last?.timestamp ?? 0
            let duration = max(0, endTS - startTS)
            let estFPS: Double = duration > 0 ? Double(c.frames.count) / duration : 0
            logger.log("[File] Candidate #\(idx + 1) frames=\(c.frames.count) peakVelocity=\(c.peakVelocity, format: .fixed(precision: 3)) ts=\(c.timestamp, privacy: .public) startTS=\(startTS, privacy: .public) endTS=\(endTS, privacy: .public) duration=\(duration, format: .fixed(precision: 3))s estFPS=\(estFPS, format: .fixed(precision: 1))")
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

        // 5) Create minimal results without AI analysis
        var results: [AnalysisResult] = []
        for swing in validated {
            let segmentMetrics = metricsCalculator.calculateSegmentMetrics(for: swing.frames)
            
            // Extract padded frames for this swing
            let (paddedPoses, paddedObjects) = extractPaddedSegmentData(
                swing: swing,
                allPoseFrames: poseFrames,
                allObjectFrames: objectFrames
            )
            
            // Create minimal AnalysisResult without AI feedback
            let result = AnalysisResult(
                segment: SwingSegment(
                    startTime: swing.frames.first?.timestamp ?? 0,
                    endTime: swing.frames.last?.timestamp ?? 0,
                    frames: paddedPoses
                ),
                swingType: swing.type,
                segmentMetrics: segmentMetrics,
                objectFrames: paddedObjects
            )
            results.append(result)
            let s = result.segment.startTime
            let e = result.segment.endTime
            let d = max(0, e - s)
            let center = (s + e) / 2.0
            logger.log("[File] Result #\(results.count) type=\(result.swingType.rawValue, privacy: .public) startTS=\(s, privacy: .public) endTS=\(e, privacy: .public) duration=\(d, format: .fixed(precision: 3))s centerTS=\(center, privacy: .public)")
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
        for swing in validated {
            let segmentMetrics = metricsCalculator.calculateSegmentMetrics(for: swing.frames)
            
            // For live session, we don't have object frames yet
            // Create empty object frames aligned with pose frames
            let emptyObjectFrames = swing.frames.map { frame in
                ObjectDetectionFrame(timestamp: frame.timestamp, racket: nil, ball: nil)
            }
            
            // Create minimal AnalysisResult without AI feedback
            let result = AnalysisResult(
                segment: SwingSegment(
                    startTime: swing.frames.first?.timestamp ?? 0,
                    endTime: swing.frames.last?.timestamp ?? 0,
                    frames: swing.frames
                ),
                swingType: swing.type,
                segmentMetrics: segmentMetrics,
                objectFrames: emptyObjectFrames
            )
            results.append(result)
            let s = result.segment.startTime
            let e = result.segment.endTime
            let d = max(0, e - s)
            let center = (s + e) / 2.0
            logger.log("[Live] Result #\(results.count) type=\(result.swingType.rawValue, privacy: .public) startTS=\(s, privacy: .public) endTS=\(e, privacy: .public) duration=\(d, format: .fixed(precision: 3))s centerTS=\(center, privacy: .public)")
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
    
    private func getVideoFPS(from url: URL) -> Double? {
        let asset = AVAsset(url: url)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            logger.warning("[File] No video track found in file")
            return nil
        }
        let fps = Double(videoTrack.nominalFrameRate)
        logger.log("[File] Video FPS detected: \(fps, format: .fixed(precision: 1))")
        return fps > 0 ? fps : nil
    }
    
}


