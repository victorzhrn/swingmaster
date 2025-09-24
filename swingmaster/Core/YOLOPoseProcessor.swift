//
//  YOLOPoseProcessor.swift
//  swingmaster
//
//  Extracts human pose using YOLO v11 Pose CoreML model.
//

import Foundation
import CoreML
import Vision
import AVFoundation
import ImageIO
import os
import CoreImage
import CoreVideo

public final class YOLOPoseProcessor {
    private let queue = DispatchQueue(label: "com.swingmaster.yolopose", qos: .userInitiated)
    private var mlModel: MLModel?
    private var inputFeatureName: String?
    private let logger = Logger(subsystem: "com.swingmaster", category: "YOLOPose")
    private var inputWidth: Int = 640
    private var inputHeight: Int = 640

    public init() {
        setupModel()
    }

    private func setupModel() {
        // Allow override for CLI/tools
        var modelURL: URL? = Bundle.main.url(forResource: "yolo11l-pose", withExtension: "mlmodelc")
        if modelURL == nil, let override = ProcessInfo.processInfo.environment["YOLO_POSE_MODEL_PATH"], !override.isEmpty {
            let candidate = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: candidate.path) {
                modelURL = candidate
            }
        }
        guard let modelURL else {
            logger.error("[Init] Pose model not found (yolo11l-pose.mlmodelc)")
            return
        }
        do {
            let config = MLModelConfiguration()
            #if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly
            #else
            config.computeUnits = .all
            #endif
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            self.mlModel = mlModel
            // Introspect image input size if available
            for (name, desc) in mlModel.modelDescription.inputDescriptionsByName {
                if desc.type == .image, let ic = desc.imageConstraint {
                    self.inputWidth = ic.pixelsWide
                    self.inputHeight = ic.pixelsHigh
                    self.inputFeatureName = name
                    logger.log("[Init] Image input size = \(self.inputWidth)×\(self.inputHeight)")
                    break
                }
            }
            logger.log("[Init] Model loaded from \(modelURL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("[Init] Failed to load pose model: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Public API

    public func processFrame(_ pixelBuffer: CVPixelBuffer,
                             timestamp: TimeInterval,
                             orientation: CGImagePropertyOrientation = .up) async -> PoseFrame? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PoseFrame?, Never>) in
            queue.async {
                guard let model = self.mlModel, let inputName = self.inputFeatureName else {
                    continuation.resume(returning: nil)
                    return
                }
                // Letterbox into model input size and keep transform
                guard let letterboxed = self.letterbox(pixelBuffer: pixelBuffer, orientation: orientation, targetWidth: self.inputWidth, targetHeight: self.inputHeight) else {
                    continuation.resume(returning: nil)
                    return
                }
                let provider = ImageFeatureProvider(imageFeatureName: inputName, pixelBuffer: letterboxed.buffer)
                do {
                    let output = try model.prediction(from: provider)
                    // Find first multiarray output
                    let arrays = output.featureNames.compactMap { name -> MLMultiArray? in
                        output.featureValue(for: name)?.multiArrayValue
                    }
                    guard let arr = arrays.first else { continuation.resume(returning: nil); return }
                    // Parse keypoints
                    var keypoints: [(x: CGFloat, y: CGFloat, c: Float)] = []
                    if let det = self.parseKeypointsFromDetections(from: arr) {
                        keypoints = det
                    } else if arr.count == 17*3 {
                        keypoints = self.parseKeypoints(from: arr)
                    } else if arr.count == 1*17*3 {
                        keypoints = self.parseKeypoints(from: arr, offset: 0)
                    } else { continuation.resume(returning: nil); return }
                    // Convert from model-space (with padding) back to source-space
                    var normalized: [(CGFloat, CGFloat, Float)] = []
                    normalized.reserveCapacity(keypoints.count)
                    for (xmNorm, ymNorm, c) in keypoints {
                        // keypoints may be already normalized 0..1 for model input; convert to pixels
                        let xm = xmNorm > 1 || ymNorm > 1 ? xmNorm : xmNorm * CGFloat(self.inputWidth)
                        let ym = ymNorm > 1 || xmNorm > 1 ? ymNorm : ymNorm * CGFloat(self.inputHeight)
                        let xs = (xm - letterboxed.padX) / letterboxed.scale
                        let ys = (ym - letterboxed.padY) / letterboxed.scale
                        let x = max(0, min(1, xs / CGFloat(letterboxed.srcWidth)))
                        // bottom-left origin for overlay
                        let y = max(0, min(1, 1.0 - (ys / CGFloat(letterboxed.srcHeight))))
                        normalized.append((x, y, min(1, max(0, c))))
                    }
                    var joints: [BodyJoint: CGPoint] = [:]
                    var conf: [BodyJoint: Float] = [:]
                    func set(_ j: BodyJoint, _ idx: Int) {
                        guard idx >= 0 && idx < normalized.count else { return }
                        joints[j] = CGPoint(x: normalized[idx].0, y: normalized[idx].1)
                        conf[j] = normalized[idx].2
                    }
                    set(.nose, 0)
                    set(.leftEye, 1)
                    set(.rightEye, 2)
                    set(.leftEar, 3)
                    set(.rightEar, 4)
                    set(.leftShoulder, 5)
                    set(.rightShoulder, 6)
                    set(.leftElbow, 7)
                    set(.rightElbow, 8)
                    set(.leftWrist, 9)
                    set(.rightWrist, 10)
                    set(.leftHip, 11)
                    set(.rightHip, 12)
                    set(.leftKnee, 13)
                    set(.rightKnee, 14)
                    set(.leftAnkle, 15)
                    set(.rightAnkle, 16)
                    if let ls = joints[.leftShoulder], let rs = joints[.rightShoulder] {
                        joints[.neck] = CGPoint(x: (ls.x + rs.x) * 0.5, y: (ls.y + rs.y) * 0.5)
                        conf[.neck] = min(conf[.leftShoulder] ?? 0, conf[.rightShoulder] ?? 0)
                    }
                    if let lh = joints[.leftHip], let rh = joints[.rightHip] {
                        joints[.root] = CGPoint(x: (lh.x + rh.x) * 0.5, y: (lh.y + rh.y) * 0.5)
                        conf[.root] = min(conf[.leftHip] ?? 0, conf[.rightHip] ?? 0)
                    }
                    let frame = PoseFrame(timestamp: timestamp, joints: joints, confidences: conf)
                    // Keep silent in steady-state; logs available in file processing
                    continuation.resume(returning: frame)
                } catch {
                    // Suppress per-frame errors; upstream will handle
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func processVideoFile(_ url: URL,
                                 targetFPS: Double = 10.0,
                                 orientation: CGImagePropertyOrientation = .right,
                                 progress: ((Float) -> Void)? = nil) async -> [PoseFrame] {
        var frames: [PoseFrame] = []
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return [] }
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }
            reader.startReading()

            let nominalFPS = max(1.0, Double(track.nominalFrameRate))
            let stride = max(1, Int(round(nominalFPS / max(1.0, targetFPS))))
            let totalDuration = CMTimeGetSeconds(asset.duration)
            var index = 0
            while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                defer { CMSampleBufferInvalidate(sample) }
                index += 1
                if index % stride != 0 { continue }
                guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
                let ts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                if let pf = await processFrame(pb, timestamp: ts, orientation: orientation) {
                    frames.append(pf)
                }
                if totalDuration.isFinite && totalDuration > 0 {
                    progress?(Float(ts / totalDuration))
                }
            }
        } catch {
            return frames
        }
        progress?(1.0)
        return frames
    }

    // MARK: - Decoding

    private func decodeResults(request: VNCoreMLRequest, timestamp: TimeInterval) -> PoseFrame? {
        // The decoding here depends on the specific YOLO pose model output format.
        // Commonly: either heatmaps+PAFs or direct [N,17,3] (x,y,score) normalized.
        // We attempt to read VNCoreMLFeatureValueObservation(s) and parse a single person.
        guard let results = request.results else { return nil }

        // Try to find a MLMultiArray of shape [17,3] or [1,17,3]
        var keypoints: [(x: CGFloat, y: CGFloat, c: Float)] = []

        for case let obs as VNCoreMLFeatureValueObservation in results {
            let fv = obs.featureValue
            if fv.type == .multiArray, let arr = fv.multiArrayValue {
                // Heuristic: flatten and try to parse 17*3 values
                let count = arr.count
                let shape = arr.shape.compactMap { ($0 as? NSNumber)?.intValue }
                if count == 17 * 3 {
                    keypoints = parseKeypoints(from: arr)
                    break
                } else if count == 1 * 17 * 3 {
                    keypoints = parseKeypoints(from: arr, offset: 0)
                    break
                } else if let det = parseKeypointsFromDetections(from: arr) {
                    keypoints = det
                    break
                }
            }
        }

        if keypoints.isEmpty { return nil }
        // Ensure coordinates are clamped and flip Y to bottom-left origin expected by UI
        // Normalize and flip coordinates
        for i in 0..<keypoints.count {
            var x = keypoints[i].x
            var y = keypoints[i].y
            // If values exceed 1, assume pixel-space and normalize by model input size
            if x > 1 || y > 1 {
                x = x / CGFloat(max(1, inputWidth))
                y = y / CGFloat(max(1, inputHeight))
            }
            x = max(0, min(1, x))
            y = 1.0 - max(0, min(1, y)) // convert to bottom-left origin
            keypoints[i] = (x, y, keypoints[i].c)
        }
        let frame = makePoseFrame(fromCOCO: keypoints, timestamp: timestamp)
        // No per-frame logs here
        return frame
    }

    // MARK: - Letterbox Rendering
    private struct LetterboxResult { let buffer: CVPixelBuffer; let scale: CGFloat; let padX: CGFloat; let padY: CGFloat; let srcWidth: Int; let srcHeight: Int }

    private func letterbox(pixelBuffer: CVPixelBuffer,
                           orientation: CGImagePropertyOrientation,
                           targetWidth: Int,
                           targetHeight: Int) -> LetterboxResult? {
        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        // Create CGImage from source with orientation applied
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let context = CIContext(options: nil)
        guard let srcCG = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        // Create destination pixel buffer
        var dstPB: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true,
                                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        CVPixelBufferCreate(kCFAllocatorDefault, targetWidth, targetHeight, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &dstPB)
        guard let outPB = dstPB else { return nil }
        CVPixelBufferLockBaseAddress(outPB, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(outPB, .readOnly) }
        guard let baseAddr = CVPixelBufferGetBaseAddress(outPB) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outPB)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(data: baseAddr, width: targetWidth, height: targetHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        // Fill black background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        // Compute scaleFit
        let s = min(CGFloat(targetWidth) / CGFloat(srcCG.width), CGFloat(targetHeight) / CGFloat(srcCG.height))
        let drawW = CGFloat(srcCG.width) * s
        let drawH = CGFloat(srcCG.height) * s
        let padX = (CGFloat(targetWidth) - drawW) / 2.0
        let padY = (CGFloat(targetHeight) - drawH) / 2.0
        ctx.interpolationQuality = .high
        ctx.draw(srcCG, in: CGRect(x: padX, y: padY, width: drawW, height: drawH))
        return LetterboxResult(buffer: outPB, scale: s, padX: padX, padY: padY, srcWidth: srcCG.width, srcHeight: srcCG.height)
    }

    private func parseKeypoints(from arr: MLMultiArray, offset: Int = 0) -> [(x: CGFloat, y: CGFloat, c: Float)] {
        var out: [(CGFloat, CGFloat, Float)] = []
        out.reserveCapacity(17)
        // Assume layout [17,3] in order (x,y,score) and values already normalized 0..1
        for i in 0..<17 {
            let base = offset + i * 3
            let x = CGFloat(truncating: arr[base])
            let y = CGFloat(truncating: arr[base + 1])
            let c = Float(truncating: arr[base + 2])
            out.append((x, y, c))
        }
        return out
    }

    /// Attempts to parse YOLO pose detection rows where last dimension is >= 5 + 17*3
    /// Common layout per row: [cx, cy, w, h, obj, kp0.x, kp0.y, kp0.c, ..., kp16.x, kp16.y, kp16.c]
    private func parseKeypointsFromDetections(from arr: MLMultiArray) -> [(x: CGFloat, y: CGFloat, c: Float)]? {
        let shape = arr.shape.compactMap { ($0 as? NSNumber)?.intValue }
        guard shape.count >= 2 else { return nil }

        // Handle common YOLO layout: [1, 56, N]
        if shape.count == 3, shape[0] == 1, shape[1] >= (5 + 17*3) {
            let attributes = shape[1]
            let anchors = shape[2]
            // Find best anchor by objectness at index 4
            var bestAnchor = 0
            var bestObj: Float = -Float.greatestFiniteMagnitude
            var indices: [NSNumber] = [0, 4, 0]
            for a in 0..<anchors {
                indices[2] = NSNumber(value: a)
                let obj = Float(truncating: arr[indices])
                if obj > bestObj { bestObj = obj; bestAnchor = a }
            }
            if bestObj <= 0 { return nil }
            var out: [(CGFloat, CGFloat, Float)] = []
            out.reserveCapacity(17)
            for k in 0..<17 {
                let baseAttr = 5 + k * 3
                indices = [0, NSNumber(value: baseAttr + 0), NSNumber(value: bestAnchor)]
                let x = CGFloat(truncating: arr[indices])
                indices[1] = NSNumber(value: baseAttr + 1)
                let y = CGFloat(truncating: arr[indices])
                indices[1] = NSNumber(value: baseAttr + 2)
                let c = Float(truncating: arr[indices])
                out.append((x, y, c))
            }
            // silent
            return out
        }

        // Fallback: try treating last dim as attributes
        let rowWidth = shape.last ?? arr.count
        let rows = max(1, arr.count / rowWidth)
        let required = 5 + 17 * 3
        guard rowWidth >= required else { return nil }
        var bestRow = 0
        var bestConf: Float = -1
        for r in 0..<rows {
            let confIndex = r * rowWidth + 4
            let conf = Float(truncating: arr[confIndex])
            if conf > bestConf { bestConf = conf; bestRow = r }
        }
        if bestConf <= 0 { return nil }
        var out: [(CGFloat, CGFloat, Float)] = []
        out.reserveCapacity(17)
        let baseKP = bestRow * rowWidth + 5
        for k in 0..<17 {
            let x = CGFloat(truncating: arr[baseKP + k * 3 + 0])
            let y = CGFloat(truncating: arr[baseKP + k * 3 + 1])
            let c = Float(truncating: arr[baseKP + k * 3 + 2])
            out.append((x, y, c))
        }
        // silent
        return out
    }

    private func makePoseFrame(fromCOCO pts: [(x: CGFloat, y: CGFloat, c: Float)], timestamp: TimeInterval) -> PoseFrame? {
        var joints: [BodyJoint: CGPoint] = [:]
        var conf: [BodyJoint: Float] = [:]
        func set(_ j: BodyJoint, _ idx: Int) {
            guard idx >= 0 && idx < pts.count else { return }
            joints[j] = CGPoint(x: pts[idx].x, y: pts[idx].y)
            conf[j] = pts[idx].c
        }
        set(.nose, 0)
        set(.leftEye, 1)
        set(.rightEye, 2)
        set(.leftEar, 3)
        set(.rightEar, 4)
        set(.leftShoulder, 5)
        set(.rightShoulder, 6)
        set(.leftElbow, 7)
        set(.rightElbow, 8)
        set(.leftWrist, 9)
        set(.rightWrist, 10)
        set(.leftHip, 11)
        set(.rightHip, 12)
        set(.leftKnee, 13)
        set(.rightKnee, 14)
        set(.leftAnkle, 15)
        set(.rightAnkle, 16)
        if let ls = joints[.leftShoulder], let rs = joints[.rightShoulder] {
            joints[.neck] = CGPoint(x: (ls.x + rs.x) * 0.5, y: (ls.y + rs.y) * 0.5)
            conf[.neck] = min(conf[.leftShoulder] ?? 0, conf[.rightShoulder] ?? 0)
        }
        if let lh = joints[.leftHip], let rh = joints[.rightHip] {
            joints[.root] = CGPoint(x: (lh.x + rh.x) * 0.5, y: (lh.y + rh.y) * 0.5)
            conf[.root] = min(conf[.leftHip] ?? 0, conf[.rightHip] ?? 0)
        }
        guard !joints.isEmpty else { return nil }
        return PoseFrame(timestamp: timestamp, joints: joints, confidences: conf)
    }
}

private final class ImageFeatureProvider: MLFeatureProvider {
    let imageFeatureName: String
    let pixelBuffer: CVPixelBuffer

    init(imageFeatureName: String, pixelBuffer: CVPixelBuffer) {
        self.imageFeatureName = imageFeatureName
        self.pixelBuffer = pixelBuffer
    }

    var featureNames: Set<String> { [imageFeatureName] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        guard featureName == imageFeatureName else { return nil }
        return MLFeatureValue(pixelBuffer: pixelBuffer)
    }
}


