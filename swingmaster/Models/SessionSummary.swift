//
//  SessionSummary.swift
//  swingmaster
//
//  Aggregated session data for display
//

import Foundation

struct SessionSummary: Codable {
    let averageScore: Float
    let shotBreakdown: [ShotType: Int]
    let totalShots: Int
    let bestShot: Shot?
    let worstShot: Shot?
    
    init(from shots: [Shot]) {
        self.totalShots = shots.count
        
        // Calculate average score
        if !shots.isEmpty {
            self.averageScore = shots.map { $0.score }.reduce(0, +) / Float(shots.count)
        } else {
            self.averageScore = 0
        }
        
        // Calculate shot breakdown
        var breakdown: [ShotType: Int] = [:]
        for shot in shots {
            breakdown[shot.type, default: 0] += 1
        }
        self.shotBreakdown = breakdown
        
        // Find best and worst shots
        self.bestShot = shots.max(by: { $0.score < $1.score })
        self.worstShot = shots.min(by: { $0.score < $1.score })
    }
}
