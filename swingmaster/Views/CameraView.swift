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

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var showingSettingsPrompt = false
    @State private var showingPermissionOverlay = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var recordedSegments: [URL] = []
    @State private var finishingSession: Bool = false

    let onRecorded: (URL) -> Void

    var body: some View {
        ZStack {
            if camera.cameraAuthStatus == .authorized && camera.micAuthGranted {
                // Embedded preview wrapper around AVCaptureVideoPreviewLayer.
                // Kept local to reduce files since it's not reused elsewhere.
                PreviewBridge(session: camera.captureSession)
                    .ignoresSafeArea()

                // Skeleton overlay (static for now)
                Image(systemName: "figure.walk")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.22)
                    .frame(width: 120, height: 120)
                    .position(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)

                VStack {
                    Spacer()

                    // Bottom bar
                    ZStack {
                        // Left slot (Upload) — hidden during active session
                        HStack {
                            if !(camera.isRecording || camera.isPaused) {
                                Button(action: { /* TODO: hook PHPicker in Phase 4 */ }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 24, weight: .regular))
                                        .foregroundColor(.white)
                                        .padding(16)
                                }
                            }
                            Spacer()
                        }

                        // Center control (Start/Pause/Resume) — always centered
                        HStack {
                            Spacer()
                            Button(action: {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()

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
                            }) {
                                Text(camera.isRecording ? "PAUSE" : (camera.isPaused ? "RESUME" : "START"))
                            }
                            .buttonStyle(RecordingButtonStyle(fillColor: camera.isRecording ? .yellow : .green))
                            Spacer()
                        }

                        // Right slot (History or END)
                        HStack {
                            Spacer()
                            if !(camera.isRecording || camera.isPaused) {
                                Button(action: { /* TODO: navigate to History in Phase 1 */ }) {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.system(size: 24, weight: .regular))
                                        .foregroundColor(.white)
                                        .padding(16)
                                }
                            } else {
                                Button(action: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    finishingSession = true
                                    stopTimer()
                                    if camera.isRecording {
                                        camera.stopRecording()
                                    } else if let last = recordedSegments.last {
                                        onRecorded(last)
                                        resetToIdle()
                                    }
                                }) {
                                    Text("END")
                                }
                                .buttonStyle(RecordingButtonStyle(fillColor: .red))
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
                        .background(Color.yellow)
                        .cornerRadius(8)

                        Button("Retry") {
                            requestPermissionsAndSetup()
                        }
                        .foregroundColor(.black)
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            requestPermissionsAndSetup()
        }
        .onChange(of: camera.lastRecordedURL) { _, newURL in
            if let url = newURL {
                // Accumulate segments. Only navigate on END.
                recordedSegments.append(url)
                if finishingSession {
                    onRecorded(url)
                    resetToIdle()
                }
            }
        }
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


