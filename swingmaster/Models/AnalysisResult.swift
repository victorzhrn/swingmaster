//
//  AnalysisResult.swift
//  swingmaster
//
//  Finalized analysis for a swing segment. In MVP this is a lightweight
//  container to be expanded by MetricsCalculator and GeminiValidator.
//

import Foundation

public struct AnalysisResult: Sendable, Identifiable {
    public var id: UUID
    public var segment: SwingSegment
    public var swingType: ShotType
    
    // Lightweight metrics and detection frames for UI/trajectory use
    public var segmentMetrics: SegmentMetrics?
    public var objectFrames: [ObjectDetectionFrame]

    public init(id: UUID = UUID(),
                segment: SwingSegment,
                swingType: ShotType,
                segmentMetrics: SegmentMetrics? = nil,
                objectFrames: [ObjectDetectionFrame] = []) {
        self.id = id
        self.segment = segment
        self.swingType = swingType
        self.segmentMetrics = segmentMetrics
        self.objectFrames = objectFrames
    }
}

/// Key frame type used by validation helpers (kept for non-AI local use)
public enum KeyFrameType: String, Sendable {
    case preparation = "Preparation"
    case backswing = "Backswing"
    case contact = "Contact"
    case followThrough = "Follow-through"
    case recovery = "Recovery"
}


