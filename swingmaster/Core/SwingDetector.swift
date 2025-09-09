//
//  SwingDetector.swift
//  swingmaster
//
//  Detects potential tennis swings by finding peaks in angular velocity and
//  extracting short candidate segments (~1s at 30fps) around each peak.
//

import Foundation

public struct PotentialSwing: Sendable {
    public let frames: [PoseFrame]
    public let peakFrameIndex: Int
    public let peakVelocity: Float
    public let timestamp: TimeInterval
}

public final class SwingDetector {
    private let peakThreshold: Float
    private let minPeakSeparationSeconds: TimeInterval
    private let beforePeakSeconds: TimeInterval
    private let afterPeakSeconds: TimeInterval
    private let assumedFPS: Int

    public init(peakThreshold: Float = 3.0,
                minPeakSeparationSeconds: TimeInterval = 1.0,
                beforePeakSeconds: TimeInterval = 0.7,
                afterPeakSeconds: TimeInterval = 0.3,
                assumedFPS: Int = 30) {
        self.peakThreshold = peakThreshold
        self.minPeakSeparationSeconds = minPeakSeparationSeconds
        self.beforePeakSeconds = beforePeakSeconds
        self.afterPeakSeconds = afterPeakSeconds
        self.assumedFPS = max(1, assumedFPS)
    }

    /// Returns potential swings given frames and their precomputed metrics.
    public func detectPotentialSwings(frames: [PoseFrame],
                                      metrics: FrameMetrics) -> [PotentialSwing] {
        let peaks = findPeaks(in: metrics.angularVelocities,
                              timestamps: frames.map { $0.timestamp },
                              threshold: peakThreshold,
                              minSeparation: minPeakSeparationSeconds)

        return peaks.compactMap { peakIndex in
            extractSegment(peakIndex: peakIndex, frames: frames, metrics: metrics)
        }
    }

    private func findPeaks(in values: [Float],
                           timestamps: [TimeInterval],
                           threshold: Float,
                           minSeparation: TimeInterval) -> [Int] {
        guard values.count == timestamps.count, values.count > 2 else { return [] }
        var result: [Int] = []
        var lastAcceptedTime: TimeInterval = -Double.greatestFiniteMagnitude

        for i in 1..<(values.count - 1) {
            let v = values[i]
            if v < threshold { continue }
            if v > values[i - 1] && v >= values[i + 1] {
                let t = timestamps[i]
                if (t - lastAcceptedTime) >= minSeparation {
                    result.append(i)
                    lastAcceptedTime = t
                }
            }
        }
        return result
    }

    private func extractSegment(peakIndex: Int,
                                frames: [PoseFrame],
                                metrics: FrameMetrics) -> PotentialSwing? {
        let framesBefore = Int(beforePeakSeconds * Double(assumedFPS))
        let framesAfter = Int(afterPeakSeconds * Double(assumedFPS))
        let startIndex = max(0, peakIndex - framesBefore)
        let endIndex = min(frames.count - 1, peakIndex + framesAfter)
        guard endIndex > startIndex, (endIndex - startIndex) >= 20 else { return nil }

        let subframes = Array(frames[startIndex...endIndex])
        let localPeakIndex = peakIndex - startIndex
        let peakVelocity = metrics.angularVelocities[peakIndex]
        let ts = frames[peakIndex].timestamp
        return PotentialSwing(frames: subframes,
                              peakFrameIndex: localPeakIndex,
                              peakVelocity: peakVelocity,
                              timestamp: ts)
    }
}


