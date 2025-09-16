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
    @StateObject private var processingManager = ProcessingManager.shared
    @StateObject private var navigationState = NavigationState()
    
    @State private var showingFilePicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack(path: $navigationState.path) {
            MainView(onSelectSession: { session in
                if session.processingStatus == .complete {
                    navigationState.push(.analysis(session))
                }
            })
            .environmentObject(sessionStore)
            .environmentObject(processingManager)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    FloatingActionMenu()
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .camera:
                    CameraView(onRecorded: { videoURL in
                        handleNewVideo(videoURL, source: .camera)
                    })
                case .analysis(let session):
                    let url = session.videoURL
                    if let persisted = AnalysisStore.load(videoURL: url) {
                        AnalysisView(videoURL: url, duration: persisted.duration, shots: persisted.shots)
                    } else {
                        AnalysisView(videoURL: url, duration: VideoStorage.getDurationSeconds(for: url), shots: [])
                    }
                case .picker:
                    EmptyView()
                }
            }
        }
        .sheet(item: $navigationState.activeSheet) { sheet in
            switch sheet {
            case .recordOptions:
                RecordOptionsModal(
                    onRecord: {
                        navigationState.push(.camera)
                    },
                    onUpload: {
                        showingFilePicker = true
                    }
                )
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            case .picker:
                EmptyView()
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
                        handleNewVideo(savedURL, source: .upload)
                    }
                }
            }
        }
        .environmentObject(sessionStore)
        .environmentObject(processingManager)
    }
    
    private enum VideoSource {
        case camera
        case upload
    }
    
    private func handleNewVideo(_ url: URL, source: VideoSource) {
        var session = Session(
            id: UUID(),
            date: Date(),
            videoPath: url.lastPathComponent,
            shotCount: 0
        )
        session.processingStatus = .pending
        
        Task {
            if let thumbnail = await VideoStorage.generateThumbnail(for: url, at: 1.0) {
                sessionStore.updateSession(session.id) { 
                    $0.thumbnailPath = thumbnail 
                }
            }
        }
        
        sessionStore.add(session)
        
        processingManager.startProcessing(
            for: session, 
            videoURL: url, 
            sessionStore: sessionStore
        )
        
        navigationState.popToRoot()
        
        withAnimation(.spring()) {
            processingManager.scrollToSession = session.id
        }
    }
    
    @ViewBuilder
    private func FloatingActionMenu() -> some View {
        FloatingActionButtonWithMenu(
            onRecord: {
                navigationState.push(.camera)
            },
            onUpload: {
                showingFilePicker = true
            }
        )
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