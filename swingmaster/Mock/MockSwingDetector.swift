//
//  MockSwingDetector.swift
//  swingmaster
//
//  Generates deterministic mock swings:
//  - One-second swings centered every 3 seconds (3s, 6s, 9s, ...)
//  - A swing is included only if its 1s window fits within the video duration
//    i.e., center in [0.5, duration - 0.5]
//  - Alternates Forehand/Backhand types
//  - Uses mocked analysis text and deterministic scores
//

import Foundation

enum MockSwingDetector {
    static func detectSwings(in videoURL: URL) -> [MockShot] {
        let duration = VideoStorage.getDurationSeconds(for: videoURL)
        guard duration > 0.5 else { return [] }

        var shots: [MockShot] = []
        var idx: Int = 0
        // Centers at 3, 6, 9, ... seconds
        var center: Double = 3.0
        while center <= (duration - 0.5) {
            if center >= 0.5 {
                let type: ShotType = (idx % 2 == 0) ? .forehand : .backhand
                let score: Float = [6.2, 7.1, 6.9, 7.9][idx % 4]
                let issues = [
                    "Contact slightly late; start swing earlier",
                    "Solid base; improve hip-shoulder separation",
                    "Follow-through short; extend through contact",
                    "Great extension; maintain wrist stability"
                ]
                let issue = issues[idx % issues.count]
                shots.append(MockShot(time: center, type: type, score: score, issue: issue))
                idx += 1
            }
            center += 3.0
        }

        return shots
    }
}


