//
//  Shot.swift
//  swingmaster
//
//  Defines shot types and shot model to support AnalysisView.
//

import Foundation
import CoreGraphics

/// Represents the type of a tennis shot.
/// Provides UI affordances like short labels and associated colors.
public enum ShotType: String, Codable, CaseIterable, Sendable {
    case forehand
    case backhand
    case serve
    case unknown

    /// Short textual label used in compact UI (chips, markers).
    var shortLabel: String {
        switch self {
        case .forehand: return "FH"
        case .backhand: return "BH"
        case .serve: return "SV"
        case .unknown: return "?"
        }
    }

    /// Accessible, human-friendly name for VoiceOver.
    var accessibleName: String {
        switch self {
        case .forehand: return "Forehand"
        case .backhand: return "Backhand"
        case .serve: return "Serve"
        case .unknown: return "Unknown"
        }
    }

    // UI color mapping removed from data layer. Provide UI colors via a UI-layer extension.
}

/// Simple model representing a detected shot in a session.
public struct Shot: Identifiable, Hashable, Codable {
    public let id: UUID
    public let time: Double  // Center time of the swing (kept for compatibility)
    public let startTime: Double  // Start of the swing segment
    public let endTime: Double    // End of the swing segment
    public let type: ShotType
    
    // Persisted minimal analytics for UI
    public let segmentMetrics: SegmentMetrics?  // Simple metrics for UI
    
    // NEW: Padded frame data for trajectory computation (swing ± 0.5s)
    public let paddedPoseFrames: [PoseFrame]
    public let paddedObjectFrames: [ObjectDetectionFrame]
    
    // Optional absolute timestamps for key frames (Preparation, Backswing, Contact, Follow Through, Recovery)
    public let keyFrameTimes: KeyFrameTimes?
    
    enum CodingKeys: String, CodingKey {
        case id, time, startTime, endTime, type
        case segmentMetrics
        case paddedPoseFrames, paddedObjectFrames
        case keyFrameTimes
    }
    
    // Custom Hashable to exclude frame data
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Shot, rhs: Shot) -> Bool {
        lhs.id == rhs.id
    }

    public init(id: UUID = UUID(), 
                time: Double, 
                type: ShotType, 
                startTime: Double? = nil, 
                endTime: Double? = nil, 
                segmentMetrics: SegmentMetrics? = nil,
                paddedPoseFrames: [PoseFrame]? = nil,
                paddedObjectFrames: [ObjectDetectionFrame]? = nil,
                keyFrameTimes: KeyFrameTimes? = nil) {
        self.id = id
        self.time = time
        // Default to 1 second swing duration if not specified
        self.startTime = startTime ?? Swift.max(0, time - 0.5)
        self.endTime = endTime ?? (time + 0.5)
        self.type = type
        self.segmentMetrics = segmentMetrics
        self.paddedPoseFrames = paddedPoseFrames ?? []
        self.paddedObjectFrames = paddedObjectFrames ?? []
        self.keyFrameTimes = keyFrameTimes
    }
    
    /// Duration of the swing in seconds
    var duration: Double {
        return endTime - startTime
    }
}

// MARK: - Sample Data (Previews)

extension Array where Element == Shot {
    /// Generates a deterministic set of sample shots across a duration.
    static func sampleShots(duration: Double) -> [Shot] {
        let times = [duration * 0.18, duration * 0.42, duration * 0.58, duration * 0.76]
        let types: [ShotType] = [.forehand, .backhand, .forehand, .backhand]
        
        // Add sample metrics
        let sampleMetrics = SegmentMetrics(
            peakAngularVelocity: 14.5,
            peakLinearVelocity: 1.2,
            contactPoint: CGPoint(x: 0.6, y: 0.45),
            backswingAngle: 95,
            followThroughHeight: 0.72,
            averageConfidence: 0.83
        )
        
        return times.enumerated().map { idx, t in
            // Create swings with realistic durations (0.8 to 1.2 seconds)
            let swingDuration = [0.9, 1.1, 0.8, 1.2][idx]  // Deterministic for previews
            let start = Swift.max(0, t - swingDuration/2)
            let end = Swift.min(duration, t + swingDuration/2)
            let shot = Shot(time: t, type: types[idx],
                            startTime: start, endTime: end,
                            segmentMetrics: sampleMetrics)
            return shot
        }
    }
}


