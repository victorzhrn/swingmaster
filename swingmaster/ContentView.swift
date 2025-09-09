//
//  ContentView.swift
//  swingmaster
//
//  Created by ruinan zhang on 2025/9/6.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var sessionStore = SessionStore()
    private enum Screen {
        case camera
        case history
        case processing
        case analysis
    }

    @State private var screen: Screen = .camera
    @State private var analysisShots: [MockShot] = []
    @State private var analysisDuration: Double = 0
    @State private var analysisVideoURL: URL?
    @State private var pendingVideoURL: URL?

    var body: some View {
        ZStack {
            switch screen {
            case .camera:
                CameraView(onRecorded: { tempURL in
                    // Persist then go to processing view
                    let savedURL = VideoStorage.saveVideo(from: tempURL)
                    pendingVideoURL = savedURL
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        screen = .processing
                    }
                }, onShowHistory: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        screen = .history
                    }
                })

            case .history:
                HistoryView(sessions: sessionStore.sessions) { session in
                    let url = session.videoURL
                    // Try to load existing analysis. If available, jump straight to AnalysisView.
                    if let persisted = AnalysisStore.load(videoURL: url) {
                        analysisVideoURL = url
                        analysisDuration = persisted.duration
                        analysisShots = persisted.shots
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            screen = .analysis
                        }
                    } else {
                        pendingVideoURL = url
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            screen = .processing
                        }
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .processing:
                if let url = pendingVideoURL {
                    ProcessingView(videoURL: url,
                                   geminiAPIKey: "AIzaSyDWvavah1RCf7acKBESKtp_vdVNf7cii8w",
                                   onComplete: { results in
                        // Map to current AnalysisView using mock-like entries for now
                        analysisVideoURL = url
                        analysisDuration = max(1, VideoStorage.getDurationSeconds(for: url))
                        analysisShots = results.enumerated().map { idx, res in
                            let t = res.segment.startTime
                            let st: ShotType = .forehand // Placeholder until AnalysisView supports real results
                            let score = max(0, min(10, res.score))
                            return MockShot(time: t, type: st, score: score, issue: res.primaryInsight)
                        }
                        // Persist analysis for future visits
                        AnalysisStore.save(videoURL: url, duration: analysisDuration, shots: analysisShots)
                        sessionStore.save(videoURL: url, shotCount: analysisShots.count)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            screen = .analysis
                        }
                    }, onCancel: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            screen = .camera
                        }
                    })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

            case .analysis:
                AnalysisView(videoURL: analysisVideoURL, duration: analysisDuration, shots: analysisShots)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if screen == .history || screen == .analysis {
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if screen == .analysis {
                                    screen = .history
                                } else {
                                    screen = .camera
                                }
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                                .font(.system(size: 18, weight: .semibold))
                                .padding(10)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview("ContentView") {
    ContentView()
        .preferredColorScheme(.dark)
}
