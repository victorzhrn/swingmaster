//
//  Shot.swift
//  swingmaster
//
//  Defines shot types and shot model to support AnalysisView.
//

import Foundation
import SwiftUI

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

    /// Color mapping aligned with design principles.
    var accentColor: Color {
        switch self {
        case .forehand: return TennisColors.tennisGreen
        case .backhand: return TennisColors.aceGreen
        case .serve: return TennisColors.clayOrange
        case .unknown: return Color.gray.opacity(0.6)
        }
    }
}

/// Simple model representing a detected shot in a session.
struct Shot: Identifiable, Hashable, Codable {
    let id: UUID
    let time: Double  // Center time of the swing (kept for compatibility)
    let startTime: Double  // Start of the swing segment
    let endTime: Double    // End of the swing segment
    let type: ShotType
    let issue: String
    
    // Transient fields - not persisted, only used during active session
    var validatedSwing: ValidatedSwing? = nil  // Store the validated swing for AI analysis
    var segmentMetrics: SegmentMetrics? = nil  // Store the metrics for AI analysis
    
    enum CodingKeys: String, CodingKey {
        case id, time, startTime, endTime, type, issue, segmentMetrics
        // Explicitly exclude validatedSwing from encoding/decoding
    }
    
    // Custom Hashable to exclude transient fields
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Shot, rhs: Shot) -> Bool {
        lhs.id == rhs.id
    }

    init(id: UUID = UUID(), time: Double, type: ShotType, issue: String, startTime: Double? = nil, endTime: Double? = nil, validatedSwing: ValidatedSwing? = nil, segmentMetrics: SegmentMetrics? = nil) {
        self.id = id
        self.time = time
        // Default to 1 second swing duration if not specified
        self.startTime = startTime ?? Swift.max(0, time - 0.5)
        self.endTime = endTime ?? (time + 0.5)
        self.type = type
        self.issue = issue
        self.validatedSwing = validatedSwing
        self.segmentMetrics = segmentMetrics
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
        let issues = [
            "Late contact",
            "Solid base, slight rotation lag",
            "Contact inconsistent",
            "Great extension"
        ]
        
        // Add sample metrics
        let sampleMetrics = SegmentMetrics(
            peakAngularVelocity: 14.5,
            peakLinearVelocity: 1.2,
            contactPoint: CGPoint(x: 0.6, y: 0.45),
            backswingAngle: 95,
            followThroughHeight: 0.72,
            averageConfidence: 0.83
        )
        
        return zip(times.indices, times).map { idx, t in
            // Create swings with realistic durations (0.8 to 1.2 seconds)
            let swingDuration = [0.9, 1.1, 0.8, 1.2][idx]  // Deterministic for previews
            let start = Swift.max(0, t - swingDuration/2)
            let end = Swift.min(duration, t + swingDuration/2)
            var shot = Shot(time: t, type: types[idx], issue: issues[idx], 
                          startTime: start, endTime: end)
            shot.segmentMetrics = sampleMetrics
            return shot
        }
    }
}


