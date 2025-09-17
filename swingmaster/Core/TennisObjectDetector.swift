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
        
        // Try both compiled and uncompiled model extensions
        let modelNames = [
            ("YOLOv3 FP16", "mlmodelc"),
            ("YOLOv3 FP16", "mlmodel"),
            ("YOLOv3_FP16", "mlmodelc"),
            ("YOLOv3_FP16", "mlmodel")
        ]
        
        var modelURL: URL?
        for (name, ext) in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                modelURL = url
                break
            }
        }
        
        guard let finalURL = modelURL else {
            print("Failed to find YOLO model in bundle")
            return
        }
        
        do {
            let mlModel = try MLModel(contentsOf: finalURL)
            let model = try VNCoreMLModel(for: mlModel)
            detectionRequest = VNCoreMLRequest(model: model)
            // Use centerCrop to match the preview layer's resizeAspectFill behavior
            detectionRequest?.imageCropAndScaleOption = .centerCrop
            print("YOLO model loaded successfully from: \(finalURL.lastPathComponent)")
        } catch {
            print("Failed to load YOLO model: \(error)")
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
}