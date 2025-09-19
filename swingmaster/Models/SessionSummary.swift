//
//  SessionSummary.swift
//  swingmaster
//
//  Aggregated session data for display
//

import Foundation

struct SessionSummary: Codable {
    let shotBreakdown: [ShotType: Int]
    let totalShots: Int
    
    init(from shots: [Shot]) {
        self.totalShots = shots.count
        
        // Calculate shot breakdown
        var breakdown: [ShotType: Int] = [:]
        for shot in shots {
            breakdown[shot.type, default: 0] += 1
        }
        self.shotBreakdown = breakdown
    }
}
