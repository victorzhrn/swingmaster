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
enum ShotType: String, Codable, CaseIterable, Sendable {
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
        case .forehand: return Color.blue
        case .backhand: return Color.green
        case .serve: return Color.purple
        case .unknown: return Color.gray
        }
    }
}

/// Simple model representing a detected or mock shot in a session.
struct MockShot: Identifiable, Hashable, Codable {
    let id: UUID
    let time: Double
    let type: ShotType
    let score: Float
    let issue: String

    init(id: UUID = UUID(), time: Double, type: ShotType, score: Float, issue: String) {
        self.id = id
        self.time = time
        self.type = type
        self.score = score
        self.issue = issue
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
            MockShot(time: t, type: types[idx], score: scores[idx], issue: issues[idx])
        }
    }
}


