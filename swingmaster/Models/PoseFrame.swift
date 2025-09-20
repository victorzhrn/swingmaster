//
//  PoseFrame.swift
//  swingmaster
//
//  One frame of normalized body pose data inferred via Vision.
//  Coordinates are normalized to the image space [0,1] where (0,0) is the
//  bottom-left in Vision space. UI layers should convert to their own
//  coordinate spaces (e.g., UIKit with origin at top-left).
//

import Foundation
import CoreGraphics
import Vision

/// A single timestamped snapshot of detected human pose.
public struct PoseFrame: Sendable, Codable {
    /// Presentation timestamp in seconds, relative to the source.
    public let timestamp: TimeInterval

    /// Normalized joint positions keyed by Vision joint names.
    /// Values are in Vision image space: x and y in [0,1], origin bottom-left.
    public let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]

    /// Confidence per joint in [0,1]. Missing joints may be absent.
    public let confidences: [VNHumanBodyPoseObservation.JointName: Float]
    
    // Internal storage for Codable - uses String keys
    private let jointsDict: [String: CGPoint]
    private let confidencesDict: [String: Float]
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case jointsDict = "joints"
        case confidencesDict = "confidences"
    }

    public init(timestamp: TimeInterval,
                joints: [VNHumanBodyPoseObservation.JointName: CGPoint],
                confidences: [VNHumanBodyPoseObservation.JointName: Float]) {
        self.timestamp = timestamp
        self.joints = joints
        self.confidences = confidences
        
        // Convert to String dictionaries for Codable
        self.jointsDict = Dictionary(uniqueKeysWithValues: joints.map { ($0.key.rawValue.rawValue, $0.value) })
        self.confidencesDict = Dictionary(uniqueKeysWithValues: confidences.map { ($0.key.rawValue.rawValue, $0.value) })
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        let jointsDict = try container.decode([String: CGPoint].self, forKey: .jointsDict)
        let confidencesDict = try container.decode([String: Float].self, forKey: .confidencesDict)
        
        // Assign to self after decoding
        self.timestamp = timestamp
        self.jointsDict = jointsDict
        self.confidencesDict = confidencesDict
        
        // Convert String dictionaries back to JointName dictionaries
        var jointsTemp: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var confidencesTemp: [VNHumanBodyPoseObservation.JointName: Float] = [:]
        
        for (key, value) in jointsDict {
            let jointName = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: key))
            jointsTemp[jointName] = value
        }
        
        for (key, value) in confidencesDict {
            let jointName = VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: key))
            confidencesTemp[jointName] = value
        }
        
        self.joints = jointsTemp
        self.confidences = confidencesTemp
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(jointsDict, forKey: .jointsDict)
        try container.encode(confidencesDict, forKey: .confidencesDict)
    }
}


