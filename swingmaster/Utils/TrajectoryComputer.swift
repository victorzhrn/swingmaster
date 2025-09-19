//
//  TrajectoryComputer.swift
//  swingmaster
//
//  On-demand trajectory extraction, gap filling, and smoothing.
//

import Foundation
import CoreGraphics
import Vision

enum TrajectoryType: String, CaseIterable, Identifiable {
    case rightWrist = "Right Wrist"
    case leftWrist = "Left Wrist"
    case rightElbow = "Right Elbow"
    case leftElbow = "Left Elbow"
    case rightShoulder = "Right Shoulder"
    case leftShoulder = "Left Shoulder"
    case racketCenter = "Racket"
    case ballCenter = "Ball"
    var id: String { rawValue }
}

struct TrajectoryOptions {
    let fillGaps: Bool
    let maxGapSeconds: Double
    let smooth: Bool
    let smoothingWindow: Int
    static let `default` = TrajectoryOptions(fillGaps: true, maxGapSeconds: 0.33, smooth: true, smoothingWindow: 3)
}

struct TrajectoryPoint: Equatable {
    let x: Float
    let y: Float
    let timestamp: Double
    let confidence: Float
    let isInterpolated: Bool
}

enum TrajectoryComputer {
    static func compute(type: TrajectoryType,
                        poseFrames: [PoseFrame],
                        objectFrames: [ObjectDetectionFrame],
                        startTime: Double,
                        options: TrajectoryOptions = .default) -> [TrajectoryPoint] {
        var points: [TrajectoryPoint]
        switch type {
        case .rightWrist:
            points = extractJoint(.rightWrist, from: poseFrames, startTime: startTime)
        case .leftWrist:
            points = extractJoint(.leftWrist, from: poseFrames, startTime: startTime)
        case .rightElbow:
            points = extractJoint(.rightElbow, from: poseFrames, startTime: startTime)
        case .leftElbow:
            points = extractJoint(.leftElbow, from: poseFrames, startTime: startTime)
        case .rightShoulder:
            points = extractJoint(.rightShoulder, from: poseFrames, startTime: startTime)
        case .leftShoulder:
            points = extractJoint(.leftShoulder, from: poseFrames, startTime: startTime)
        case .racketCenter:
            points = extractRacket(from: objectFrames, startTime: startTime)
        case .ballCenter:
            points = extractBall(from: objectFrames, startTime: startTime)
        }

        if options.fillGaps, points.count > 1 {
            let interval = estimateFrameInterval(points: points) ?? (1.0 / 30.0)
            let maxGapFrames = Int(round(options.maxGapSeconds / interval))
            points = fillGaps(points, maxGapFrames: maxGapFrames, frameInterval: interval)
        }
        if options.smooth, points.count > options.smoothingWindow {
            points = smooth(points, windowSize: options.smoothingWindow)
        }
        return points
    }

    // MARK: - Extraction

    private static func extractJoint(_ joint: VNHumanBodyPoseObservation.JointName,
                                     from frames: [PoseFrame],
                                     startTime: Double) -> [TrajectoryPoint] {
        frames.compactMap { frame in
            guard let point = frame.joints[joint], let conf = frame.confidences[joint], conf > 0.3 else { return nil }
            return TrajectoryPoint(x: Float(point.x),
                                   y: Float(point.y),
                                   timestamp: frame.timestamp - startTime,
                                   confidence: conf,
                                   isInterpolated: false)
        }
    }

    private static func extractRacket(from frames: [ObjectDetectionFrame], startTime: Double) -> [TrajectoryPoint] {
        frames.compactMap { f in
            guard let r = f.racket, r.confidence > 0.3 else { return nil }
            return TrajectoryPoint(x: Float(r.boundingBox.midX),
                                   y: Float(r.boundingBox.midY),
                                   timestamp: f.timestamp - startTime,
                                   confidence: r.confidence,
                                   isInterpolated: false)
        }
    }

    private static func extractBall(from frames: [ObjectDetectionFrame], startTime: Double) -> [TrajectoryPoint] {
        frames.compactMap { f in
            guard let b = f.ball, b.confidence > 0.3 else { return nil }
            return TrajectoryPoint(x: Float(b.boundingBox.midX),
                                   y: Float(b.boundingBox.midY),
                                   timestamp: f.timestamp - startTime,
                                   confidence: b.confidence,
                                   isInterpolated: false)
        }
    }

    // MARK: - Gap Fill & Smoothing

    static func estimateFrameInterval(points: [TrajectoryPoint]) -> Double? {
        let deltas = zip(points.dropFirst(), points).map { $0.0.timestamp - $0.1.timestamp }.filter { $0 > 0 }
        guard !deltas.isEmpty else { return nil }
        let sorted = deltas.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[mid - 1] + sorted[mid]) / 2.0 } else { return sorted[mid] }
    }

    static func fillGaps(_ pts: [TrajectoryPoint], maxGapFrames: Int, frameInterval: Double) -> [TrajectoryPoint] {
        var out: [TrajectoryPoint] = []
        guard let first = pts.first else { return pts }
        out.append(first)
        for i in 1..<pts.count {
            let prev = pts[i-1]
            let curr = pts[i]
            let timeDiff = curr.timestamp - prev.timestamp
            let gap = Int((timeDiff / frameInterval).rounded()) - 1
            if gap > 0 && gap <= maxGapFrames {
                for j in 1...gap {
                    let t = Float(j) / Float(gap + 1)
                    let interp = TrajectoryPoint(
                        x: prev.x + (curr.x - prev.x) * t,
                        y: prev.y + (curr.y - prev.y) * t,
                        timestamp: prev.timestamp + Double(j) * frameInterval,
                        confidence: min(prev.confidence, curr.confidence) * 0.7,
                        isInterpolated: true
                    )
                    out.append(interp)
                }
            }
            out.append(curr)
        }
        return out
    }

    static func smooth(_ pts: [TrajectoryPoint], windowSize: Int) -> [TrajectoryPoint] {
        guard pts.count > windowSize else { return pts }
        var out: [TrajectoryPoint] = []
        for i in 0..<pts.count {
            let start = max(0, i - windowSize/2)
            let end = min(pts.count - 1, i + windowSize/2)
            var sx: Float = 0, sy: Float = 0, c: Float = 0
            for j in start...end { sx += pts[j].x; sy += pts[j].y; c += 1 }
            out.append(TrajectoryPoint(x: sx / c, y: sy / c, timestamp: pts[i].timestamp, confidence: pts[i].confidence, isInterpolated: pts[i].isInterpolated))
        }
        return out
    }
}


