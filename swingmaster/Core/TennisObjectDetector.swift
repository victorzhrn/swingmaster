//
//  TennisObjectDetector.swift
//  swingmaster
//
//  YOLO-based tennis ball and racket detection
//

import Foundation
import Vision
import CoreML
import CoreVideo
import ImageIO
import UIKit
import AVFoundation

class TennisObjectDetector {
    private var detectionRequest: VNCoreMLRequest?
    private let detectionQueue = DispatchQueue(label: "com.swingmaster.yolo", qos: .userInitiated)
    
    struct Detection {
        let racketBox: CGRect?      // Normalized coordinates
        let ballBox: CGRect?        // Normalized coordinates
        let racketConfidence: Float
        let ballConfidence: Float
        let timestamp: TimeInterval
    }
    
    init() {
        setupModel()
    }
    
    private func setupModel() {
        // Check if running in preview
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        if isPreview {
            print("Running in Preview - skipping YOLO model load")
            return
        }
        
        // Load compiled YOLO11 model from bundle
        guard let modelURL = Bundle.main.url(forResource: "yolo11l", withExtension: "mlmodelc") else {
            print("Failed to find YOLO11 model (yolo11l.mlmodelc) in bundle")
            return
        }
        
        do {
            var config = MLModelConfiguration()
            config.computeUnits = .all
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            let model = try VNCoreMLModel(for: mlModel)
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            self.detectionRequest = request
            print("YOLO11 model loaded successfully: yolo11l.mlmodelc")
        } catch {
            print("Failed to load YOLO11 model: \(error)")
        }
    }
    
    func detectObjects(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, orientation: CGImagePropertyOrientation = .up) async -> Detection? {
        return await withCheckedContinuation { continuation in
            guard let request = detectionRequest else {
                continuation.resume(returning: nil)
                return
            }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
            
            detectionQueue.async {
                do {
                    try handler.perform([request])
                    
                    guard let results = request.results as? [VNRecognizedObjectObservation] else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let detection = self.parseResults(results, timestamp: timestamp)
                    continuation.resume(returning: detection)
                } catch {
                    print("YOLO detection error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func parseResults(_ results: [VNRecognizedObjectObservation], timestamp: TimeInterval) -> Detection {
        var racketBox: CGRect?
        var ballBox: CGRect?
        var racketConfidence: Float = 0
        var ballConfidence: Float = 0
        
        for observation in results {
            guard let topLabel = observation.labels.first else { continue }
            
            let label = topLabel.identifier.lowercased()
            let confidence = topLabel.confidence
            
            // Look for tennis racket or sports ball
            if label.contains("tennis") && label.contains("racket") && confidence > racketConfidence {
                racketBox = observation.boundingBox
                racketConfidence = confidence
            } else if (label.contains("sports") && label.contains("ball")) || label.contains("tennis ball") {
                if confidence > ballConfidence {
                    ballBox = observation.boundingBox
                    ballConfidence = confidence
                }
            }
        }
        
        return Detection(
            racketBox: racketBox,
            ballBox: ballBox,
            racketConfidence: racketConfidence,
            ballConfidence: ballConfidence,
            timestamp: timestamp
        )
    }

    // MARK: - File-based detection (on-demand)
    /// Run object detection on a video file between start and end times.
    /// Returns an array of ObjectDetectionFrame aligned to frame timestamps.
    /// This is designed for short segments (e.g., a single shot window).
    func detectObjects(in url: URL,
                       start: TimeInterval,
                       end: TimeInterval,
                       orientation: CGImagePropertyOrientation = .right,
                       confidenceThreshold: Float = 0.3) async -> [ObjectDetectionFrame] {
        var frames: [ObjectDetectionFrame] = []

        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return [] }

        let startTime = max(0, start)
        let endTime = min(CMTimeGetSeconds(asset.duration), max(start, end))
        guard endTime > startTime else { return [] }

        let timeRange = CMTimeRangeFromTimeToTime(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )

        let readerSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        do {
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = timeRange

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }

            reader.startReading()

            while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                defer { CMSampleBufferInvalidate(sample) }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let timestamp = CMTimeGetSeconds(pts)

                if let det = await detectObjects(pixelBuffer, timestamp: timestamp, orientation: orientation) {
                    let racket: RacketDetection? = (det.racketBox != nil && det.racketConfidence >= confidenceThreshold)
                        ? RacketDetection(boundingBox: det.racketBox!, confidence: det.racketConfidence, timestamp: timestamp)
                        : nil

                    let ball: BallDetection? = (det.ballBox != nil && det.ballConfidence >= confidenceThreshold)
                        ? BallDetection(boundingBox: det.ballBox!, confidence: det.ballConfidence, timestamp: timestamp)
                        : nil

                    frames.append(ObjectDetectionFrame(timestamp: timestamp, racket: racket, ball: ball))
                } else {
                    frames.append(ObjectDetectionFrame(timestamp: timestamp, racket: nil, ball: nil))
                }
            }
        } catch {
            return frames
        }

        return frames
    }
}