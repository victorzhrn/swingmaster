//
//  ObjectDetection.swift
//  swingmaster
//
//  Tennis ball and racket detection data models for YOLO integration
//

import Foundation
import CoreGraphics

struct RacketDetection: Sendable {
    let boundingBox: CGRect    // Normalized 0-1
    let confidence: Float
    let timestamp: TimeInterval
}

struct BallDetection: Sendable {
    let boundingBox: CGRect    // Normalized 0-1
    let confidence: Float
    let timestamp: TimeInterval
}

struct ObjectDetectionFrame: Sendable {
    let timestamp: TimeInterval
    let racket: RacketDetection?
    let ball: BallDetection?
}