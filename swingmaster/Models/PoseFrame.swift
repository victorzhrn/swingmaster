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
public struct PoseFrame: Sendable {
    /// Presentation timestamp in seconds, relative to the source.
    public let timestamp: TimeInterval

    /// Normalized joint positions keyed by Vision joint names.
    /// Values are in Vision image space: x and y in [0,1], origin bottom-left.
    public let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]

    /// Confidence per joint in [0,1]. Missing joints may be absent.
    public let confidences: [VNHumanBodyPoseObservation.JointName: Float]

    public init(timestamp: TimeInterval,
                joints: [VNHumanBodyPoseObservation.JointName: CGPoint],
                confidences: [VNHumanBodyPoseObservation.JointName: Float]) {
        self.timestamp = timestamp
        self.joints = joints
        self.confidences = confidences
    }
}


