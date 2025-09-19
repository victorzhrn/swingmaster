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
    public var keyFrames: [KeyFrame]
    
    // Store these for on-demand AI analysis
    public var validatedSwing: ValidatedSwing?
    public var segmentMetrics: SegmentMetrics?

    public init(id: UUID = UUID(),
                segment: SwingSegment,
                swingType: ShotType,
                keyFrames: [KeyFrame],
                validatedSwing: ValidatedSwing? = nil,
                segmentMetrics: SegmentMetrics? = nil) {
        self.id = id
        self.segment = segment
        self.swingType = swingType
        self.keyFrames = keyFrames
        self.validatedSwing = validatedSwing
        self.segmentMetrics = segmentMetrics
    }
}

/// Simplified key frame reference used for tracking important moments
public struct KeyFrame: Sendable {
    public let type: KeyFrameType
    public let frameIndex: Int
    public let timestamp: TimeInterval

    public init(type: KeyFrameType, frameIndex: Int, timestamp: TimeInterval) {
        self.type = type
        self.frameIndex = frameIndex
        self.timestamp = timestamp
    }
}

public enum KeyFrameType: String, Sendable {
    case preparation = "Preparation"
    case backswing = "Backswing"
    case contact = "Contact"
    case followThrough = "Follow-through"
    case recovery = "Recovery"
}


