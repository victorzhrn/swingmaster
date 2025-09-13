//
//  ContentView.swift
//  swingmaster
//
//  Created by ruinan zhang on 2025/9/6.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var sessionStore = SessionStore()
    
    private enum NavigationState {
        case main
        case camera
        case processing(URL)
        case analysis(URL, Double, [MockShot])
    }
    
    @State private var navigationState: NavigationState = .main
    @State private var showingFilePicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    
    var body: some View {
        ZStack {
            switch navigationState {
            case .main:
                MainView(onSelectSession: { session in
                    let url = session.videoURL
                    if let persisted = AnalysisStore.load(videoURL: url) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            navigationState = .analysis(url, persisted.duration, persisted.shots)
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            navigationState = .processing(url)
                        }
                    }
                })
                    .environmentObject(sessionStore)
                    .overlay(alignment: .bottomTrailing) {
                        FloatingActionMenu()
                    }
                    .transition(.opacity)
                
            case .camera:
                CameraView(onRecorded: { tempURL in
                    let savedURL = VideoStorage.saveVideo(from: tempURL)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        navigationState = .processing(savedURL)
                    }
                })
                .overlay(alignment: .topLeading) {
                    BackButton {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            navigationState = .main
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.top, 12)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                
            case .processing(let url):
                ProcessingView(
                    videoURL: url,
                    geminiAPIKey: "AIzaSyDWvavah1RCf7acKBESKtp_vdVNf7cii8w",
                    onComplete: { results in
                        let duration = max(1, VideoStorage.getDurationSeconds(for: url))
                        let shots = results.map { res in
                            let t = (res.segment.startTime + res.segment.endTime) / 2.0
                            let score = max(0, min(10, res.score))
                            return MockShot(
                                id: res.id,
                                time: t,
                                type: res.swingType,
                                score: score,
                                issue: res.improvements.first ?? "",
                                startTime: res.segment.startTime,
                                endTime: res.segment.endTime,
                                strengths: res.strengths,
                                improvements: res.improvements
                            )
                        }
                        
                        // Persist analysis
                        AnalysisStore.save(videoURL: url, duration: duration, shots: shots)
                        sessionStore.save(videoURL: url, shotCount: shots.count)
                        
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            navigationState = .analysis(url, duration, shots)
                        }
                    },
                    onCancel: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            navigationState = .main
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                
            case .analysis(let url, let duration, let shots):
                AnalysisView(videoURL: url, duration: duration, shots: shots)
                    .overlay(alignment: .topLeading) {
                        BackButton {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                navigationState = .main
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.top, 12)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .photosPicker(
            isPresented: $showingFilePicker,
            selection: $selectedVideoItem,
            matching: .videos
        )
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let item = newItem else { return }
            
            Task {
                if let movie = try? await item.loadTransferable(type: Movie.self) {
                    let savedURL = VideoStorage.saveVideo(from: movie.url)
                    await MainActor.run {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            navigationState = .processing(savedURL)
                        }
                    }
                }
            }
        }
        .environmentObject(sessionStore)
    }
    
    @ViewBuilder
    private func FloatingActionMenu() -> some View {
        if case .main = navigationState {
            FloatingActionButtonWithMenu(
                onRecord: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        navigationState = .camera
                    }
                },
                onUpload: {
                    showingFilePicker = true
                }
            )
            .padding(.trailing, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Supporting Views

struct BackButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .semibold))
                .padding(10)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct FloatingActionButtonWithMenu: View {
    let onRecord: () -> Void
    let onUpload: () -> Void
    @State private var showingOptions = false
    
    var body: some View {
        FloatingActionButton(isPressed: $showingOptions)
            .sheet(isPresented: $showingOptions) {
                RecordOptionsModal(
                    onRecord: {
                        showingOptions = false
                        onRecord()
                    },
                    onUpload: {
                        showingOptions = false
                        onUpload()
                    }
                )
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
    }
}

// MARK: - Movie Transfer Type

struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

#Preview("ContentView") {
    ContentView()
        .preferredColorScheme(.dark)
}
