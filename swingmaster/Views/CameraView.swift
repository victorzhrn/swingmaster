//
//  CameraView.swift
//  swingmaster
//
//  Full-screen camera with skeleton overlay and bottom controls (upload, record, history).
//  Integrates a Start/Pause/Resume button style as requested, implemented inline.
//

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var showingSettingsPrompt = false
    @State private var showingPermissionOverlay = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var recordedSegments: [URL] = []
    @State private var finishingSession: Bool = false
    @State private var isProcessing: Bool = false
    @State private var showingPicker: Bool = false
    @State private var showSkeleton: Bool = true
    @State private var showObjects: Bool = true

    let onRecorded: (URL) -> Void

    /// Returns true when rendering inside Xcode Previews so that we can bypass
    /// hardware permissions/session setup and still display the intended UI.
    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ZStack {
            if (camera.cameraAuthStatus == .authorized && camera.micAuthGranted) || isRunningInPreview {
                // Embedded preview wrapper around AVCaptureVideoPreviewLayer.
                // Kept local to reduce files since it's not reused elsewhere.
                if isRunningInPreview {
                    // Placeholder background in Previews
                    Color.black.ignoresSafeArea()
                } else {
                    PreviewBridge(session: camera.captureSession)
                        .ignoresSafeArea()
                }

                if showSkeleton {
                    // Assume 16:9 capture for AVCaptureVideoPreviewLayer; pass aspect and use fill to match preview layer
                    SkeletonOverlay(pose: camera.latestPose, videoAspectRatio: 16.0/9.0, contentMode: .fill)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                if showObjects {
                    RacketOverlay(detection: camera.latestRacket)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    BallOverlay(detection: camera.latestBall)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                VStack {
                    Spacer()

                    // Bottom bar
                    ZStack {
                        // Left slot (empty)
                        HStack { Spacer() }

                        // Center control (Start/Pause/Resume) — always centered
                        HStack {
                            Spacer()
                            Button(action: {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()

                                if isProcessing { return }
                                if isRunningInPreview {
                                    // Simulate recording in previews without AVFoundation
                                    if camera.isRecording {
                                        camera.pause()
                                        stopTimer()
                                    } else if camera.isPaused {
                                        camera.resume()
                                        startTimer()
                                    } else {
                                        elapsedTime = 0
                                        recordedSegments.removeAll()
                                        finishingSession = false
                                        // Simulate start (no real recording)
                                        camera.isRecording = true
                                        startTimer()
                                    }
                                } else {
                                    if camera.isRecording {
                                        camera.pause()
                                        stopTimer()
                                    } else if camera.isPaused {
                                        camera.resume()
                                        startTimer()
                                    } else {
                                        elapsedTime = 0
                                        recordedSegments.removeAll()
                                        finishingSession = false
                                        camera.start()
                                        startTimer()
                                    }
                                }
                            }) {
                                Text(camera.isRecording ? "PAUSE" : (camera.isPaused ? "RESUME" : "START"))
                            }
                            .buttonStyle(RecordingButtonStyle(fillColor: camera.isRecording ? .yellow : .green))
                            .disabled(isProcessing)
                            Spacer()
                        }

                        // Right slot (END only)
                        HStack {
                            Spacer()
                            if (camera.isRecording || camera.isPaused) {
                                Button(action: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    finishingSession = true
                                    stopTimer()
                                    if isProcessing { return }
                                    if isRunningInPreview {
                                        // Simulate stop & deliver a mock URL after 2s
                                        camera.isRecording = false
                                        isProcessing = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            let fakeURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("preview.mov")
                                            onRecorded(fakeURL)
                                            isProcessing = false
                                            resetToIdle()
                                        }
                                    } else if camera.isRecording {
                                        camera.stopRecording()
                                    } else if let last = recordedSegments.last {
                                        // Already have a segment; show processing overlay then navigate
                                        isProcessing = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            onRecorded(last)
                                            isProcessing = false
                                            resetToIdle()
                                        }
                                    }
                                }) {
                                    Text("END")
                                }
                                .buttonStyle(RecordingButtonStyle(fillColor: .red))
                                .disabled(isProcessing)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                // Recording HUD (timer)
                VStack {
                    HStack {
                        if camera.isRecording {
                            Circle().fill(Color.red).frame(width: 10, height: 10)
                        }
                        Text(timeString(elapsedTime))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(String(format: " · %.1f fps", camera.processedFPS))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }
            } else {
                // Permission overlay when denied or not determined
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                    Text("Camera & Microphone Access Needed")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("Enable access to record your tennis swings and capture audio.")
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    HStack(spacing: 12) {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(.black)
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .background(TennisColors.tennisYellow)
                        .cornerRadius(8)

                        Button("Retry") {
                            requestPermissionsAndSetup()
                        }
                        .foregroundColor(.black)
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .background(TennisColors.tennisGreen)
                        .cornerRadius(8)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if !isRunningInPreview {
                requestPermissionsAndSetup()
            }
        }
        .onChange(of: camera.lastRecordedURL) { _, newURL in
            if let url = newURL {
                // Accumulate segments. Only navigate on END.
                recordedSegments.append(url)
                if finishingSession {
                    // Show processing before navigating to analysis
                    isProcessing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        onRecorded(url)
                        isProcessing = false
                        resetToIdle()
                    }
                }
            }
        }
        .overlay(
            Group {
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Processing…")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
        )
        .overlay(alignment: .topTrailing) {
            if !(camera.isRecording || camera.isPaused) {
                HStack(spacing: 8) {
                    Button(action: { withAnimation { showSkeleton.toggle() } }) {
                        Image(systemName: showSkeleton ? "figure.walk" : "figure.walk.slash")
                            .foregroundColor(showSkeleton ? .white : .gray)
                    }
                    .buttonStyle(OverlayToggleStyle())
                    .accessibilityLabel(showSkeleton ? "Hide skeleton overlay" : "Show skeleton overlay")
                    
                    Button(action: { withAnimation { showObjects.toggle() } }) {
                        Image(systemName: "tennisball")
                            .foregroundColor(showObjects ? TennisColors.tennisYellow : .gray)
                    }
                    .buttonStyle(OverlayToggleStyle())
                    .accessibilityLabel(showObjects ? "Hide object detection" : "Show object detection")
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
            }
        }
        // Upload removed in MVP MainView flow
    }

    private func requestPermissionsAndSetup() {
        camera.requestPermissions { cameraGranted, micGranted in
            if cameraGranted && micGranted {
                camera.configureSessionIfNeeded()
                camera.startSession()
            } else {
                showingPermissionOverlay = true
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            elapsedTime += 0.5
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timeString(_ t: TimeInterval) -> String {
        let seconds = Int(t.rounded())
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func resetToIdle() {
        finishingSession = false
        camera.isPaused = false
        elapsedTime = 0
        recordedSegments.removeAll()
    }

    // Upload flow removed
}

// MARK: - RecordingButtonStyle (inline style matching reference)

private struct RecordingButtonStyle: ButtonStyle {
    let fillColor: Color
    private let pressedScale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .bold, design: .monospaced))
            .frame(width: 100, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .shadow(color: fillColor.opacity(0.5), radius: configuration.isPressed ? 4 : 8)
    }
}

// MARK: - Local Preview Bridge (UIKit layer)

/// Minimal UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer, kept local to this file
/// for reduced surface area per the user's preference. If preview is needed elsewhere later,
/// this type can be promoted to Components/.
private struct PreviewBridge: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: - OverlayToggleStyle

private struct OverlayToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - VideoPicker (PHPicker wrapper)

private struct VideoPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            let provider = result.itemProvider
            let movieIdentifier = UTType.movie.identifier
            if provider.hasItemConformingToTypeIdentifier(movieIdentifier) {
                provider.loadFileRepresentation(forTypeIdentifier: movieIdentifier) { url, error in
                    guard let url = url else { return }
                    // Copy to a new temp location we control
                    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                    let dest = tempDir.appendingPathComponent(UUID().uuidString + ".mov")
                    do {
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.copyItem(at: url, to: dest)
                        DispatchQueue.main.async { self.onPicked(dest) }
                    } catch {
                        // Ignore failure silently for MVP
                    }
                }
            }
        }
    }
}

#Preview("CameraView") {
    CameraView { url in
        print("Recorded video at: \(url)")
    }
}
