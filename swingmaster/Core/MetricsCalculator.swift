//
//  MetricsCalculator.swift
//  swingmaster
//
//  Centralized metrics computation for pose-derived kinematics.
//  Produces per-frame metrics and segment summaries with light smoothing.
//

import Foundation
import CoreGraphics
import Vision

/// Joint angle measurements for a single frame.
public struct JointAngles: Sendable {
    public let leftElbow: Float?
    public let rightElbow: Float?
    public let leftShoulder: Float?
    public let rightShoulder: Float?
    public let leftHip: Float?
    public let rightHip: Float?
}

/// Per-frame metrics across a sequence of `PoseFrame`s.
public struct FrameMetrics: Sendable {
    public let angularVelocities: [Float]
    public let linearVelocities: [Float]
    public let jointAngles: [JointAngles]
    public let shoulderRotation: [Float]
    public let hipRotation: [Float]
    public let wristHeights: [Float]
}

/// Summary metrics for a contiguous swing segment.
public struct SegmentMetrics: Sendable, Codable {
    public let peakAngularVelocity: Float
    public let peakLinearVelocity: Float
    public let contactPoint: CGPoint
    public let backswingAngle: Float
    public let followThroughHeight: Float
    public let averageConfidence: Float
}

/// Computes kinematic metrics from pose frames with simple smoothing.
/// Methods favor the right side joints and gracefully fall back to the left side when unavailable.
public final class MetricsCalculator {
    private let velocityWindowSize: Int
    private let angleWindowSize: Int

    public init(velocityWindowSize: Int = 5, angleWindowSize: Int = 3) {
        self.velocityWindowSize = max(1, velocityWindowSize)
        self.angleWindowSize = max(1, angleWindowSize)
    }

    /// Computes all frame metrics for a sequence of frames.
    public func calculateMetrics(for frames: [PoseFrame]) -> FrameMetrics {
        let rawAngular = calculateAngularVelocity(frames)
        let rawLinear = calculateLinearVelocity(frames)
        let angles = calculateJointAngles(frames)
        let shoulder = calculateShoulderRotation(frames)
        let hip = calculateHipRotation(frames)
        let wristY = calculateWristHeights(frames)

        let angularSmoothed = movingAverage(rawAngular, window: velocityWindowSize)
        let linearSmoothed = movingAverage(rawLinear, window: velocityWindowSize)
        let shoulderSmoothed = movingAverage(shoulder, window: angleWindowSize)
        let hipSmoothed = movingAverage(hip, window: angleWindowSize)
        let wristYSmoothed = movingAverage(wristY, window: angleWindowSize)

        return FrameMetrics(
            angularVelocities: angularSmoothed,
            linearVelocities: linearSmoothed,
            jointAngles: angles,
            shoulderRotation: shoulderSmoothed,
            hipRotation: hipSmoothed,
            wristHeights: wristYSmoothed
        )
    }

    /// Approximates angular velocity (rad/s) of the wrist around the shoulder by differentiating the angle of the wrist vector relative to the shoulder across time.
    public func calculateAngularVelocity(_ frames: [PoseFrame]) -> [Float] {
        guard frames.count >= 2 else { return Array(repeating: 0, count: frames.count) }

        var result: [Float] = Array(repeating: 0, count: frames.count)
        var previousAngle: Double?
        var previousTime: Double?

        for (index, frame) in frames.enumerated() {
            let side = chooseDominantSide(in: frame)
            let shoulderName: VNHumanBodyPoseObservation.JointName = (side == .right) ? .rightShoulder : .leftShoulder
            let wristName: VNHumanBodyPoseObservation.JointName = (side == .right) ? .rightWrist : .leftWrist

            guard let shoulder = frame.joints[shoulderName], let wrist = frame.joints[wristName] else {
                previousAngle = nil
                previousTime = nil
                continue
            }

            let angle = atan2(Double(wrist.y - shoulder.y), Double(wrist.x - shoulder.x))
            if let pa = previousAngle, let pt = previousTime {
                let dt = max(1e-3, frame.timestamp - pt)
                var dTheta = angle - pa
                // unwrap to shortest path
                if dTheta > .pi { dTheta -= 2 * .pi }
                if dTheta < -.pi { dTheta += 2 * .pi }
                result[index] = Float(dTheta / dt)
            }
            previousAngle = angle
            previousTime = frame.timestamp
        }

        return result
    }

    /// Approximates linear wrist speed (units/s in normalized image space).
    public func calculateLinearVelocity(_ frames: [PoseFrame]) -> [Float] {
        guard frames.count >= 2 else { return Array(repeating: 0, count: frames.count) }
        var result: [Float] = Array(repeating: 0, count: frames.count)

        var previousPoint: CGPoint?
        var previousTime: Double?

        for (index, frame) in frames.enumerated() {
            let side = chooseDominantSide(in: frame)
            let wristName: VNHumanBodyPoseObservation.JointName = (side == .right) ? .rightWrist : .leftWrist

            guard let wrist = frame.joints[wristName] else {
                previousPoint = nil
                previousTime = nil
                continue
            }

            if let pp = previousPoint, let pt = previousTime {
                let dx = Double(wrist.x - pp.x)
                let dy = Double(wrist.y - pp.y)
                let dist = sqrt(dx * dx + dy * dy)
                let dt = max(1e-3, frame.timestamp - pt)
                result[index] = Float(dist / dt)
            }

            previousPoint = wrist
            previousTime = frame.timestamp
        }

        return result
    }

    /// Computes selected joint angles (degrees) for each frame.
    public func calculateJointAngles(_ frames: [PoseFrame]) -> [JointAngles] {
        return frames.map { frame in
            let le = angleAtJoint(center: .leftElbow, a: .leftWrist, b: .leftShoulder, in: frame)
            let re = angleAtJoint(center: .rightElbow, a: .rightWrist, b: .rightShoulder, in: frame)
            let ls = angleAtJoint(center: .leftShoulder, a: .leftElbow, b: .leftHip, in: frame)
            let rs = angleAtJoint(center: .rightShoulder, a: .rightElbow, b: .rightHip, in: frame)
            let lh = angleAtJoint(center: .leftHip, a: .leftKnee, b: .leftShoulder, in: frame)
            let rh = angleAtJoint(center: .rightHip, a: .rightKnee, b: .rightShoulder, in: frame)
            return JointAngles(
                leftElbow: le,
                rightElbow: re,
                leftShoulder: ls,
                rightShoulder: rs,
                leftHip: lh,
                rightHip: rh
            )
        }
    }

    /// Computes rotation of the shoulder line (right-shoulder to left-shoulder) relative to horizontal, in degrees.
    public func calculateShoulderRotation(_ frames: [PoseFrame]) -> [Float] {
        return frames.map { frame in
            guard let l = frame.joints[.leftShoulder], let r = frame.joints[.rightShoulder] else { return 0 }
            let angle = atan2(Double(l.y - r.y), Double(l.x - r.x))
            return Float(angle * 180.0 / .pi)
        }
    }

    /// Computes rotation of the hip line (right-hip to left-hip) relative to horizontal, in degrees.
    public func calculateHipRotation(_ frames: [PoseFrame]) -> [Float] {
        return frames.map { frame in
            guard let l = frame.joints[.leftHip], let r = frame.joints[.rightHip] else { return 0 }
            let angle = atan2(Double(l.y - r.y), Double(l.x - r.x))
            return Float(angle * 180.0 / .pi)
        }
    }

    /// Tracks dominant wrist height (normalized y in [0,1]).
    public func calculateWristHeights(_ frames: [PoseFrame]) -> [Float] {
        return frames.map { frame in
            let side = chooseDominantSide(in: frame)
            let wristName: VNHumanBodyPoseObservation.JointName = (side == .right) ? .rightWrist : .leftWrist
            guard let p = frame.joints[wristName] else { return 0 }
            return Float(p.y)
        }
    }

    /// Computes summary metrics for a swing segment based on its frames.
    public func calculateSegmentMetrics(for segment: [PoseFrame]) -> SegmentMetrics {
        let frameMetrics = calculateMetrics(for: segment)
        let angular = frameMetrics.angularVelocities
        let linear = frameMetrics.linearVelocities

        let peakAngular = angular.max() ?? 0
        let peakAngularIndex = angular.firstIndex(of: peakAngular) ?? 0
        let peakLinear = linear.max() ?? 0

        let contactIndex = peakAngularIndex
        let contactWristPoint: CGPoint = {
            let frame = segment[min(max(0, contactIndex), segment.count - 1)]
            let side = chooseDominantSide(in: frame)
            let wristName: VNHumanBodyPoseObservation.JointName = (side == .right) ? .rightWrist : .leftWrist
            return frame.joints[wristName] ?? .zero
        }()

        // Backswing angle as maximum shoulder rotation prior to contact
        let backswingAngle: Float = {
            let pre = frameMetrics.shoulderRotation.prefix(contactIndex)
            return pre.max() ?? 0
        }()

        // Follow-through height as maximum wrist height after contact
        let followThroughHeight: Float = {
            let post = frameMetrics.wristHeights.suffix(from: min(contactIndex, frameMetrics.wristHeights.count))
            return post.max() ?? 0
        }()

        // Average joint confidence across frames and joints
        let averageConfidence: Float = {
            guard !segment.isEmpty else { return 0 }
            var total: Double = 0
            var count: Double = 0
            for f in segment {
                for (_, c) in f.confidences { total += Double(c); count += 1 }
            }
            return count > 0 ? Float(total / count) : 0
        }()

        return SegmentMetrics(
            peakAngularVelocity: peakAngular,
            peakLinearVelocity: peakLinear,
            contactPoint: contactWristPoint,
            backswingAngle: backswingAngle,
            followThroughHeight: followThroughHeight,
            averageConfidence: averageConfidence
        )
    }

    // MARK: - Helpers

    private enum DominantSide { case left, right }

    private func chooseDominantSide(in frame: PoseFrame) -> DominantSide {
        // Prefer right if wrist available; otherwise left
        if frame.joints[.rightWrist] != nil { return .right }
        if frame.joints[.leftWrist] != nil { return .left }
        // Fallback: prefer right for consistency
        return .right
    }

    private func angleAtJoint(center: VNHumanBodyPoseObservation.JointName,
                              a: VNHumanBodyPoseObservation.JointName,
                              b: VNHumanBodyPoseObservation.JointName,
                              in frame: PoseFrame) -> Float? {
        guard let c = frame.joints[center], let pa = frame.joints[a], let pb = frame.joints[b] else { return nil }
        let v1 = CGVector(dx: pa.x - c.x, dy: pa.y - c.y)
        let v2 = CGVector(dx: pb.x - c.x, dy: pb.y - c.y)
        let dot = Double(v1.dx * v2.dx + v1.dy * v2.dy)
        let mag1 = Double(hypot(v1.dx, v1.dy))
        let mag2 = Double(hypot(v2.dx, v2.dy))
        guard mag1 > 1e-6, mag2 > 1e-6 else { return nil }
        let cosTheta = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        let angle = acos(cosTheta)
        return Float(angle * 180.0 / .pi)
    }

    private func movingAverage(_ values: [Float], window: Int) -> [Float] {
        guard window > 1, values.count > 1 else { return values }
        let n = values.count
        var output = values
        var sum: Double = 0
        var q: [Double] = []
        q.reserveCapacity(window)
        for i in 0..<n {
            sum += Double(values[i])
            q.append(Double(values[i]))
            if q.count > window { sum -= q.removeFirst() }
            output[i] = Float(sum / Double(q.count))
        }
        return output
    }
}


