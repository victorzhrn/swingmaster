//
//  PoseProcessor.swift
//  swingmaster
//
//  Vision integration to extract human body pose from pixel buffers and
//  video files. Provides timestamped PoseFrame outputs on a background queue.
//

import Foundation
import AVFoundation
import Vision

/// Extracts human pose using Vision. Thread-safe across calls.
final class PoseProcessor {
    private let visionQueue = DispatchQueue(label: "com.swingmaster.vision", qos: .userInitiated)
    private let request: VNDetectHumanBodyPoseRequest

    init() {
        self.request = VNDetectHumanBodyPoseRequest()
        // Default revision; can be adjusted later if needed.
    }

    /// Process a single frame and return a PoseFrame if a person is detected.
    /// - Parameter pixelBuffer: Source frame pixel buffer (BGRA recommended).
    /// - Returns: PoseFrame or nil if no valid observation.
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval = CACurrentMediaTime()) async -> PoseFrame? {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                do {
                    try handler.perform([self.request])
                    guard let observation = (self.request.results as? [VNHumanBodyPoseObservation])?.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let frame = Self.makePoseFrame(from: observation, timestamp: timestamp)
                    continuation.resume(returning: frame)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Process a video file at a reduced sampling rate (~10 fps) to control cost.
    /// - Parameter progress: Optional callback reporting 0..1 extraction progress.
    /// - Returns: Array of PoseFrame in chronological order.
    func processVideoFile(_ url: URL, targetFPS: Double = 10.0, progress: ((Float) -> Void)? = nil) async -> [PoseFrame] {
        var frames: [PoseFrame] = []

        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return [] }
        let readerSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }

            reader.startReading()

            // Compute stride to approximate targetFPS
            let nominalFrameRate = Double(track.nominalFrameRate)
            let stride = max(1, Int(round(nominalFrameRate / max(1.0, targetFPS))))
            var index = 0

            let totalDuration = CMTimeGetSeconds(asset.duration)
            while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                defer { CMSampleBufferInvalidate(sample) }
                index += 1
                if index % stride != 0 { continue }

                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let ts = CMTimeGetSeconds(pts)
                if let pf = await processFrame(pixelBuffer, timestamp: ts) {
                    frames.append(pf)
                }
                if totalDuration.isFinite && totalDuration > 0 {
                    let ratio = max(0, min(1, Float(ts / totalDuration)))
                    progress?(ratio)
                }
            }
        } catch {
            return frames
        }

        progress?(1.0)
        return frames
    }

    private static func makePoseFrame(from observation: VNHumanBodyPoseObservation, timestamp: TimeInterval) -> PoseFrame? {
        do {
            let recognized = try observation.recognizedPoints(.all)
            var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
            var confidences: [VNHumanBodyPoseObservation.JointName: Float] = [:]

            for (name, point) in recognized {
                // Only keep valid points
                guard point.confidence > 0 else { continue }
                let clamped = CGPoint(x: max(0, min(1, point.location.x)),
                                      y: max(0, min(1, point.location.y)))
                joints[name] = clamped
                confidences[name] = point.confidence
            }

            guard !joints.isEmpty else { return nil }
            return PoseFrame(timestamp: timestamp, joints: joints, confidences: confidences)
        } catch {
            return nil
        }
    }
}


