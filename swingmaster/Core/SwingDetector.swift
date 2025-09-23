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
    public let angularVelocities: [Float]
}

public final class SwingDetector {
    private let peakThreshold: Float
    private let minPeakSeparationSeconds: TimeInterval
    private let beforePeakSeconds: TimeInterval
    private let afterPeakSeconds: TimeInterval

    public init(peakThreshold: Float = 3.0,
                minPeakSeparationSeconds: TimeInterval = 1.0,
                beforePeakSeconds: TimeInterval = 0.8,
                afterPeakSeconds: TimeInterval = 1.2) {
        self.peakThreshold = peakThreshold
        self.minPeakSeparationSeconds = minPeakSeparationSeconds
        self.beforePeakSeconds = beforePeakSeconds
        self.afterPeakSeconds = afterPeakSeconds
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
        guard !frames.isEmpty, peakIndex >= 0, peakIndex < frames.count else { return nil }
        let peakTime = frames[peakIndex].timestamp
        let targetStartTime = max(0, peakTime - beforePeakSeconds)
        let targetEndTime = peakTime + afterPeakSeconds

        // Find nearest indices to target times using timestamps (FPS-agnostic)
        var startIndex = peakIndex
        while startIndex > 0 && frames[startIndex].timestamp > targetStartTime { startIndex -= 1 }
        var endIndex = peakIndex
        while endIndex < frames.count - 1 && frames[endIndex].timestamp < targetEndTime { endIndex += 1 }

        // Ensure minimum span of ~20 frames to keep enough context
        if endIndex - startIndex < 20 {
            let deficit = 20 - (endIndex - startIndex)
            let growLeft = deficit / 2
            let growRight = deficit - growLeft
            startIndex = max(0, startIndex - growLeft)
            endIndex = min(frames.count - 1, endIndex + growRight)
        }
        guard endIndex > startIndex else { return nil }

        let subframes = Array(frames[startIndex...endIndex])
        let localPeakIndex = max(0, min(peakIndex - startIndex, subframes.count - 1))
        let peakVelocity = metrics.angularVelocities[peakIndex]
        let ts = frames[peakIndex].timestamp
        return PotentialSwing(frames: subframes,
                              peakFrameIndex: localPeakIndex,
                              peakVelocity: peakVelocity,
                              timestamp: ts,
                              angularVelocities: Array(metrics.angularVelocities[startIndex...endIndex]))
    }
}


