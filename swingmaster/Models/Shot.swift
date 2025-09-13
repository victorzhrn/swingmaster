//
//  Shot.swift
//  swingmaster
//
//  Defines shot types and a simple mock shot model to support AnalysisView.
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
        case .backhand: return TennisColors.courtGreen
        case .serve: return TennisColors.clayOrange
        case .unknown: return Color.gray
        }
    }
}

/// Simple model representing a detected or mock shot in a session.
struct MockShot: Identifiable, Hashable, Codable {
    let id: UUID
    let time: Double  // Center time of the swing (kept for compatibility)
    let startTime: Double  // Start of the swing segment
    let endTime: Double    // End of the swing segment
    let type: ShotType
    let score: Float
    let issue: String
    // Coaching details (optional for now; filled from AnalysisResult)
    let strengths: [String]?
    let improvements: [String]?

    init(id: UUID = UUID(), time: Double, type: ShotType, score: Float, issue: String, startTime: Double? = nil, endTime: Double? = nil, strengths: [String]? = nil, improvements: [String]? = nil) {
        self.id = id
        self.time = time
        // Default to 1 second swing duration if not specified
        self.startTime = startTime ?? Swift.max(0, time - 0.5)
        self.endTime = endTime ?? (time + 0.5)
        self.type = type
        self.score = score
        self.issue = issue
        self.strengths = strengths
        self.improvements = improvements
    }
    
    /// Duration of the swing in seconds
    var duration: Double {
        return endTime - startTime
    }
}

// MARK: - Sample Data (Previews)

extension Array where Element == MockShot {
    /// Generates a deterministic set of sample shots across a duration.
    static func sampleShots(duration: Double) -> [MockShot] {
        let times = [duration * 0.18, duration * 0.42, duration * 0.58, duration * 0.76]
        let types: [ShotType] = [.forehand, .backhand, .forehand, .backhand]
        let scores: [Float] = [6.2, 7.1, 6.9, 7.9]
        let issues = [
            "Late contact",
            "Solid base, slight rotation lag",
            "Contact inconsistent",
            "Great extension"
        ]
        return zip(times.indices, times).map { idx, t in
            // Create swings with realistic durations (0.8 to 1.2 seconds)
            let swingDuration = [0.9, 1.1, 0.8, 1.2][idx]  // Deterministic for previews
            let start = Swift.max(0, t - swingDuration/2)
            let end = Swift.min(duration, t + swingDuration/2)
            return MockShot(time: t, type: types[idx], score: scores[idx], issue: issues[idx], 
                          startTime: start, endTime: end)
        }
    }
}


