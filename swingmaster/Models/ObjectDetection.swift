//
//  ObjectDetection.swift
//  swingmaster
//
//  Tennis ball and racket detection data models for YOLO integration
//

import Foundation
import CoreGraphics

public struct RacketDetection: Sendable, Codable {
    public let boundingBox: CGRect    // Normalized 0-1
    public let confidence: Float
    public let timestamp: TimeInterval
    
    public init(boundingBox: CGRect, confidence: Float, timestamp: TimeInterval) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public struct BallDetection: Sendable, Codable {
    public let boundingBox: CGRect    // Normalized 0-1
    public let confidence: Float
    public let timestamp: TimeInterval
    
    public init(boundingBox: CGRect, confidence: Float, timestamp: TimeInterval) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public struct ObjectDetectionFrame: Sendable, Codable {
    public let timestamp: TimeInterval
    public let racket: RacketDetection?
    public let ball: BallDetection?
    
    public init(timestamp: TimeInterval, racket: RacketDetection? = nil, ball: BallDetection? = nil) {
        self.timestamp = timestamp
        self.racket = racket
        self.ball = ball
    }
}