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
    /// Select the smoothing algorithm to apply to trajectories.
    enum SmoothingMethod {
        case none
        case savitzkyGolay(polyOrder: Int)
    }

    /// Select the interpolation method for filling short gaps.
    enum GapMethod {
        case linear
        case cubicSpline
    }

    let smoothingMethod: SmoothingMethod
    let gapMethod: GapMethod

    /// Defaults tuned for 30 FPS: SG window 5 (~0.17s) with quadratic fit, cubic gap fill.
    static let `default` = TrajectoryOptions(
        fillGaps: true,
        maxGapSeconds: 0.33,
        smooth: true,
        smoothingWindow: 7,
        smoothingMethod: .savitzkyGolay(polyOrder: 2),
        gapMethod: .cubicSpline
    )
}

struct TrajectoryPoint: Equatable {
    let x: Float
    let y: Float
    let timestamp: Double
    let confidence: Float
    let isInterpolated: Bool
    
    // Motion quality indicators
    let velocity: Float?        // Speed in normalized units per second
    let acceleration: Float?    // Acceleration in normalized units per second²
    let isPowerSpot: Bool       // True if this is a peak velocity point
    
    // Convenience initializer for backward compatibility
    init(x: Float, y: Float, timestamp: Double, confidence: Float, isInterpolated: Bool,
         velocity: Float? = nil, acceleration: Float? = nil, isPowerSpot: Bool = false) {
        self.x = x
        self.y = y
        self.timestamp = timestamp
        self.confidence = confidence
        self.isInterpolated = isInterpolated
        self.velocity = velocity
        self.acceleration = acceleration
        self.isPowerSpot = isPowerSpot
    }
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
            switch options.gapMethod {
            case .linear:
                points = fillGapsLinear(points, maxGapFrames: maxGapFrames, frameInterval: interval)
            case .cubicSpline:
                points = fillGapsCubic(points, maxGapFrames: maxGapFrames, frameInterval: interval)
            }
        }
        if options.smooth, points.count > options.smoothingWindow {
            switch options.smoothingMethod {
            case .none:
                break
            case .savitzkyGolay(let polyOrder):
                points = smoothSavitzkyGolay(points, windowSize: options.smoothingWindow, polyOrder: polyOrder)
            }
        }
        
        // Calculate motion metrics (velocity, acceleration, power spots)
        points = calculateMotionMetrics(points)
        
        return points
    }

    // MARK: - Extraction

    private static func extractJoint(_ joint: VNHumanBodyPoseObservation.JointName,
                                     from frames: [PoseFrame],
                                     startTime: Double) -> [TrajectoryPoint] {
        frames.compactMap { frame in
            guard let point = frame.joints[joint], let conf = frame.confidences[joint], conf > 0.3 else { 
                return nil 
            }
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

    // MARK: - Motion Metrics Calculation
    
    /// Calculate velocity, acceleration, and identify power spots in the trajectory
    private static func calculateMotionMetrics(_ points: [TrajectoryPoint]) -> [TrajectoryPoint] {
        guard points.count > 2 else { return points }
        
        var velocities: [Float] = []
        var accelerations: [Float] = []
        
        // Calculate velocities using central differences
        for i in 0..<points.count {
            let velocity: Float
            
            if i == 0 && points.count > 1 {
                // Forward difference for first point
                let dx = points[1].x - points[0].x
                let dy = points[1].y - points[0].y
                let dt = Float(points[1].timestamp - points[0].timestamp)
                velocity = dt > 0 ? sqrt(dx*dx + dy*dy) / dt : 0
            } else if i == points.count - 1 && points.count > 1 {
                // Backward difference for last point
                let dx = points[i].x - points[i-1].x
                let dy = points[i].y - points[i-1].y
                let dt = Float(points[i].timestamp - points[i-1].timestamp)
                velocity = dt > 0 ? sqrt(dx*dx + dy*dy) / dt : 0
            } else if i > 0 && i < points.count - 1 {
                // Central difference for middle points
                let dx = points[i+1].x - points[i-1].x
                let dy = points[i+1].y - points[i-1].y
                let dt = Float(points[i+1].timestamp - points[i-1].timestamp)
                velocity = dt > 0 ? sqrt(dx*dx + dy*dy) / dt : 0
            } else {
                velocity = 0
            }
            
            velocities.append(velocity)
        }
        
        // Calculate accelerations using central differences on velocities
        for i in 0..<velocities.count {
            let acceleration: Float
            
            if i == 0 && velocities.count > 1 && points.count > 1 {
                // Forward difference
                let dv = velocities[1] - velocities[0]
                let dt = Float(points[1].timestamp - points[0].timestamp)
                acceleration = dt > 0 ? dv / dt : 0
            } else if i == velocities.count - 1 && velocities.count > 1 && i > 0 {
                // Backward difference
                let dv = velocities[i] - velocities[i-1]
                let dt = Float(points[i].timestamp - points[i-1].timestamp)
                acceleration = dt > 0 ? dv / dt : 0
            } else if i > 0 && i < velocities.count - 1 {
                // Central difference
                let dv = velocities[i+1] - velocities[i-1]
                let dt = Float(points[i+1].timestamp - points[i-1].timestamp)
                acceleration = dt > 0 ? dv / dt : 0
            } else {
                acceleration = 0
            }
            
            accelerations.append(acceleration)
        }
        
        // Identify power spots (local maxima in velocity)
        var powerSpots: [Bool] = Array(repeating: false, count: points.count)
        
        // Find the 90th percentile velocity as threshold for power spots
        let sortedVelocities = velocities.sorted()
        let percentileIndex = Int(Double(sortedVelocities.count) * 0.9)
        let velocityThreshold = sortedVelocities[min(percentileIndex, sortedVelocities.count - 1)]
        
        // Mark local maxima above threshold as power spots
        for i in 1..<velocities.count - 1 {
            if velocities[i] >= velocityThreshold &&
               velocities[i] > velocities[i-1] &&
               velocities[i] > velocities[i+1] {
                powerSpots[i] = true
            }
        }
        
        // Create new trajectory points with motion metrics
        var enhancedPoints: [TrajectoryPoint] = []
        for i in 0..<points.count {
            let point = points[i]
            let enhanced = TrajectoryPoint(
                x: point.x,
                y: point.y,
                timestamp: point.timestamp,
                confidence: point.confidence,
                isInterpolated: point.isInterpolated,
                velocity: velocities[i],
                acceleration: accelerations[i],
                isPowerSpot: powerSpots[i]
            )
            enhancedPoints.append(enhanced)
        }
        
        return enhancedPoints
    }

    // MARK: - Gap Fill & Smoothing

    static func estimateFrameInterval(points: [TrajectoryPoint]) -> Double? {
        let deltas = zip(points.dropFirst(), points).map { $0.0.timestamp - $0.1.timestamp }.filter { $0 > 0 }
        guard !deltas.isEmpty else { return nil }
        let sorted = deltas.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[mid - 1] + sorted[mid]) / 2.0 } else { return sorted[mid] }
    }

    /// Linear gap filling preserving timestamps; maintains existing behavior for compatibility.
    static func fillGapsLinear(_ pts: [TrajectoryPoint], maxGapFrames: Int, frameInterval: Double) -> [TrajectoryPoint] {
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

    /// Cubic (Hermite/Catmull-Rom style) interpolation for short gaps using neighboring keyframes
    /// to estimate tangents. Produces natural curved paths for racket/ball and joints.
    static func fillGapsCubic(_ pts: [TrajectoryPoint], maxGapFrames: Int, frameInterval: Double) -> [TrajectoryPoint] {
        var out: [TrajectoryPoint] = []
        guard !pts.isEmpty else { return pts }
        out.append(pts[0])
        for i in 1..<pts.count {
            let prev = pts[i-1]
            let curr = pts[i]
            let timeDiff = curr.timestamp - prev.timestamp
            let gap = Int((timeDiff / frameInterval).rounded()) - 1
            if gap > 0 && gap <= maxGapFrames {
                let prev2: TrajectoryPoint? = (i-2) >= 0 ? pts[i-2] : nil
                let next2: TrajectoryPoint? = (i+1) < pts.count ? pts[i+1] : nil
                // Tangent estimates for Catmull-Rom: m0 ~ (curr - prev2)/2, m1 ~ (next2 - prev)/2
                let m0x: Float = {
                    if let p2 = prev2 { return (curr.x - p2.x) * 0.5 } else { return (curr.x - prev.x) }
                }()
                let m0y: Float = {
                    if let p2 = prev2 { return (curr.y - p2.y) * 0.5 } else { return (curr.y - prev.y) }
                }()
                let m1x: Float = {
                    if let n2 = next2 { return (n2.x - prev.x) * 0.5 } else { return (curr.x - prev.x) }
                }()
                let m1y: Float = {
                    if let n2 = next2 { return (n2.y - prev.y) * 0.5 } else { return (curr.y - prev.y) }
                }()

                for j in 1...gap {
                    let u = Float(j) / Float(gap + 1) // 0..1
                    let u2 = u * u
                    let u3 = u2 * u
                    // Cubic Hermite basis
                    let h00 = 2*u3 - 3*u2 + 1
                    let h10 = u3 - 2*u2 + u
                    let h01 = -2*u3 + 3*u2
                    let h11 = u3 - u2
                    let ix = h00 * prev.x + h10 * m0x + h01 * curr.x + h11 * m1x
                    let iy = h00 * prev.y + h10 * m0y + h01 * curr.y + h11 * m1y
                    let interp = TrajectoryPoint(
                        x: ix,
                        y: iy,
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

    /// Savitzky–Golay smoothing via local polynomial regression around each point.
    /// - Parameters:
    ///   - pts: Input trajectory points
    ///   - windowSize: Odd number of samples in window (e.g., 5 or 7)
    ///   - polyOrder: Polynomial order (e.g., 2)
    /// - Returns: Smoothed trajectory preserving sharp features
    static func smoothSavitzkyGolay(_ pts: [TrajectoryPoint], windowSize: Int, polyOrder: Int) -> [TrajectoryPoint] {
        guard pts.count > windowSize, windowSize % 2 == 1, polyOrder >= 1, polyOrder < windowSize else { return pts }
        var out: [TrajectoryPoint] = []
        let half = windowSize / 2

        for i in 0..<pts.count {
            let start = max(0, i - half)
            let end = min(pts.count - 1, i + half)
            // Build t offsets centered at i (not necessarily symmetric at edges)
            var tValues: [Double] = []
            tValues.reserveCapacity(end - start + 1)
            for j in start...end { tValues.append(Double(j - i)) }
            let count = tValues.count
            // X and Y series over window
            var xVals: [Double] = []
            var yVals: [Double] = []
            xVals.reserveCapacity(count)
            yVals.reserveCapacity(count)
            for j in start...end { xVals.append(Double(pts[j].x)); yVals.append(Double(pts[j].y)) }

            // Compute intercepts via normal equations; if solver fails, fallback to moving average
            if let x0 = solveLeastSquaresIntercept(t: tValues, y: xVals, polyOrder: polyOrder),
               let y0 = solveLeastSquaresIntercept(t: tValues, y: yVals, polyOrder: polyOrder) {
                out.append(TrajectoryPoint(x: Float(x0), y: Float(y0), timestamp: pts[i].timestamp, confidence: pts[i].confidence, isInterpolated: pts[i].isInterpolated))
            } else {
                // Fallback: keep original point if regression fails
                out.append(pts[i])
            }
        }
        return out
    }

    /// Solve for intercept (value at t=0) of polynomial least squares fit of given order.
    /// Uses normal equations and Gaussian elimination. Small matrices only (order <= 5 recommended).
    private static func solveLeastSquaresIntercept(t: [Double], y: [Double], polyOrder: Int) -> Double? {
        let n = polyOrder + 1
        guard t.count == y.count, t.count >= n else { return nil }

        // Build ATA (n x n) and ATy (n)
        var ata = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var aty = Array(repeating: 0.0, count: n)
        for idx in 0..<t.count {
            var tpowers = Array(repeating: 1.0, count: n)
            for p in 1..<n { tpowers[p] = tpowers[p-1] * t[idx] }
            for r in 0..<n {
                aty[r] += tpowers[r] * y[idx]
                for c in 0..<n { ata[r][c] += tpowers[r] * tpowers[c] }
            }
        }

        // Solve ata * beta = aty
        guard let beta = gaussianEliminationSolve(a: ata, b: aty) else { return nil }
        // Intercept is beta[0] (value at t=0)
        return beta.first
    }

    /// Simple Gaussian elimination with partial pivoting for small dense systems.
    private static func gaussianEliminationSolve(a: [[Double]], b: [Double]) -> [Double]? {
        let n = b.count
        guard a.count == n, a[0].count == n else { return nil }
        var A = a
        var B = b
        // Forward elimination
        for k in 0..<n {
            // Pivot
            var pivot = k
            var maxVal = abs(A[k][k])
            for r in (k+1)..<n {
                if abs(A[r][k]) > maxVal { maxVal = abs(A[r][k]); pivot = r }
            }
            if maxVal == 0 { return nil }
            if pivot != k { A.swapAt(k, pivot); B.swapAt(k, pivot) }
            // Eliminate
            let akk = A[k][k]
            for r in (k+1)..<n {
                let factor = A[r][k] / akk
                if factor == 0 { continue }
                for c in k..<n { A[r][c] -= factor * A[k][c] }
                B[r] -= factor * B[k]
            }
        }
        // Back substitution
        var x = Array(repeating: 0.0, count: n)
        for i in stride(from: n-1, through: 0, by: -1) {
            var sum = B[i]
            for j in (i+1)..<n { sum -= A[i][j] * x[j] }
            let diag = A[i][i]
            if diag == 0 { return nil }
            x[i] = sum / diag
        }
        return x
    }
}


