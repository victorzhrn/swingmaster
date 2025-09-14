//
//  ContactPointDetector.swift
//  swingmaster
//
//  Detects contact points between tennis ball and racket using proximity analysis
//

import Foundation
import CoreGraphics

class ContactPointDetector {
    struct ContactEvent {
        let timestamp: TimeInterval
        let position: CGPoint       // Normalized
        let confidence: Float
        let racketBox: CGRect
        let ballBox: CGRect
    }
    
    private var lastBallPosition: CGPoint?
    private var lastRacketBox: CGRect?
    
    func detectContact(racket: RacketDetection?, 
                      ball: BallDetection?) -> ContactEvent? {
        guard let racket = racket, 
              let ball = ball,
              racket.confidence > 0.7,
              ball.confidence > 0.5 else { return nil }
        
        // Check if ball is within or near racket bounds
        let expandedRacket = racket.boundingBox.insetBy(dx: -0.02, dy: -0.02)
        let ballCenter = CGPoint(
            x: ball.boundingBox.midX,
            y: ball.boundingBox.midY
        )
        
        if expandedRacket.contains(ballCenter) {
            return ContactEvent(
                timestamp: racket.timestamp,
                position: ballCenter,
                confidence: min(racket.confidence, ball.confidence),
                racketBox: racket.boundingBox,
                ballBox: ball.boundingBox
            )
        }
        
        return nil
    }
}