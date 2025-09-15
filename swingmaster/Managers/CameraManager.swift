//
//  CameraManager.swift
//  swingmaster
//
//  Manages the camera capture session, permissions, and basic movie recording.
//  Aligned with Core Architecture: kept lightweight and UI-agnostic so it can be
//  extended later to stream frames into Vision (PoseProcessor) without changing UI.
//

import Foundation
import AVFoundation
import Vision
import ImageIO

/// CameraManager is responsible for:
/// - Requesting camera & microphone permissions
/// - Configuring and owning an AVCaptureSession
/// - Starting/stopping the session
/// - Starting/stopping basic movie recording with auto-stop at max duration
///
/// Notes:
/// - "Pause/Resume" is modeled as toggling recording on/off. Resuming starts a new clip.
///   Concatenation is out of scope for MVP and can be added later in the processing pipeline.
final class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning: Bool = false
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var cameraAuthStatus: AVAuthorizationStatus = .notDetermined
    @Published var micAuthGranted: Bool = false
    @Published var lastRecordedURL: URL?
    @Published var errorMessage: String?

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.swingmaster.camera.session")
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataQueue = DispatchQueue(label: "com.swingmaster.camera.frames", qos: .userInitiated)

    // Pose processing
    private let poseProcessor = PoseProcessor()
    private var frameCount: Int = 0

    // Object detection
    private let objectDetector = TennisObjectDetector()
    @Published var latestRacket: RacketDetection?
    @Published var latestBall: BallDetection?
    
    // Preview support
    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    // Latest pose for UI overlay
    @Published var latestPose: PoseFrame?
    @Published var processedFPS: Double = 0

    // FPS calculation
    private var fpsWindowCount: Int = 0
    private var fpsWindowStart: TimeInterval = CACurrentMediaTime()

    /// Exposes the session for preview rendering.
    var captureSession: AVCaptureSession { session }

    // MARK: - Permissions

    /// Requests camera and microphone permissions concurrently.
    func requestPermissions(completion: @escaping (_ cameraGranted: Bool, _ micGranted: Bool) -> Void) {
        // In preview, just pretend permissions are granted
        if isRunningInPreview {
            self.cameraAuthStatus = .authorized
            self.micAuthGranted = true
            completion(true, true)
            return
        }
        
        let group = DispatchGroup()
        var cameraGranted = false
        var micGranted = false

        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraGranted = granted
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            DispatchQueue.main.async {
                self.cameraAuthStatus = status
            }
            group.leave()
        }

        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micGranted = granted
            DispatchQueue.main.async {
                self.micAuthGranted = granted
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(cameraGranted, micGranted)
        }
    }

    // MARK: - Session Lifecycle

    /// Configures inputs/outputs. Safe to call multiple times; does nothing if already configured.
    func configureSessionIfNeeded() {
        // Skip session configuration in previews
        if isRunningInPreview {
            print("Running in Preview - skipping camera session configuration")
            return
        }
        
        sessionQueue.async {
            guard self.session.inputs.isEmpty else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            do {
                // Video input (back camera)
                if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    if self.session.canAddInput(videoInput) {
                        self.session.addInput(videoInput)
                    }
                }

                // Audio input (microphone)
                if let audioDevice = AVCaptureDevice.default(for: .audio) {
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                    if self.session.canAddInput(audioInput) {
                        self.session.addInput(audioInput)
                    }
                }

                // Movie output
                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }

                // Video data output (for Vision)
                self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.videoDataOutput) {
                    self.session.addOutput(self.videoDataOutput)
                }
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataQueue)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Camera configuration failed: \(error.localizedDescription)"
                }
            }

            self.session.commitConfiguration()
        }
    }

    func startSession() {
        if isRunningInPreview {
            isSessionRunning = true
            return
        }
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isSessionRunning = true }
        }
    }

    func stopSession() {
        if isRunningInPreview {
            isSessionRunning = false
            return
        }
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    // MARK: - Recording

    /// Starts recording to a temporary file and auto-stops at `maxDuration` seconds.
    func startRecording(maxDuration: TimeInterval = 10) {
        guard !movieOutput.isRecording else { return }

        // Defensive: ensure session is running and we have a video connection before starting.
        guard session.isRunning, movieOutput.connection(with: .video) != nil else {
            DispatchQueue.main.async {
                self.errorMessage = "Camera not available to record."
            }
            return
        }

        let tempURL = Self.temporaryMovieURL()
        // Configure max duration
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 30)
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)

        DispatchQueue.main.async {
            self.isRecording = true
            self.isPaused = false
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        DispatchQueue.main.async { self.isRecording = false }
    }

    /// UI-level semantic controls matching the Start/Pause/Resume button behavior.
    func start() {
        startRecording()
    }

    func pause() {
        // For MVP, treat pause as stop recording; preview continues.
        stopRecording()
        DispatchQueue.main.async { self.isPaused = true }
    }

    func resume() {
        // Start a new clip on resume.
        startRecording()
        DispatchQueue.main.async { self.isPaused = false }
    }

    private static func temporaryMovieURL() -> URL {
        let fileName = UUID().uuidString + ".mov"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.errorMessage = "Recording failed: \(error.localizedDescription)"
            } else {
                self.lastRecordedURL = outputFileURL
            }
            self.isRecording = false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        // Sample at ~10 fps from a 30 fps source.
        if frameCount % 3 != 0 { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = CMTimeGetSeconds(pts)
        
        // Get the proper orientation for Vision framework
        // For back camera in portrait mode, we typically need .right
        let orientation: CGImagePropertyOrientation = .right

        Task { [weak self] in
            guard let self = self else { return }
            
            // Run both detections concurrently
            async let poseTask = self.poseProcessor.processFrame(pixelBuffer, timestamp: timestamp)
            async let objectTask = self.objectDetector.detectObjects(pixelBuffer, timestamp: timestamp, orientation: orientation)
            
            let (pose, objectDetection) = await (poseTask, objectTask)
            
            await MainActor.run {
                self.latestPose = pose
                
                if let detection = objectDetection {
                    // Update racket detection
                    if let racketBox = detection.racketBox, detection.racketConfidence > 0.3 {
                        self.latestRacket = RacketDetection(
                            boundingBox: racketBox,
                            confidence: detection.racketConfidence,
                            timestamp: detection.timestamp
                        )
                    } else {
                        self.latestRacket = nil
                    }
                    
                    // Update ball detection
                    if let ballBox = detection.ballBox, detection.ballConfidence > 0.3 {
                        self.latestBall = BallDetection(
                            boundingBox: ballBox,
                            confidence: detection.ballConfidence,
                            timestamp: detection.timestamp
                        )
                    } else {
                        self.latestBall = nil
                    }
                } else {
                    self.latestRacket = nil
                    self.latestBall = nil
                }
            }
        }

        // Update FPS window on processed frames
        fpsWindowCount += 1
        let now = CACurrentMediaTime()
        let delta = now - fpsWindowStart
        if delta >= 1.0 {
            let fps = Double(fpsWindowCount) / delta
            fpsWindowStart = now
            fpsWindowCount = 0
            DispatchQueue.main.async { self.processedFPS = fps }
        }
    }
}


