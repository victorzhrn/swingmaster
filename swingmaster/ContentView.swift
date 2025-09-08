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
        case analysis
    }

    @State private var screen: Screen = .camera
    @State private var analysisShots: [MockShot] = []
    @State private var analysisDuration: Double = 0
    @State private var analysisVideoURL: URL?

    var body: some View {
        ZStack {
            switch screen {
            case .camera:
                CameraView(onRecorded: { tempURL in
                    // Persist video, create session entry, and navigate with real URL & mock shots
                    let savedURL = VideoStorage.saveVideo(from: tempURL)
                    let duration = VideoStorage.getDurationSeconds(for: savedURL)
                    analysisDuration = duration > 0 ? duration : 90
                    analysisShots = MockSwingDetector.detectSwings(in: savedURL)
                    analysisVideoURL = savedURL
                    sessionStore.save(videoURL: savedURL, shotCount: analysisShots.count)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        screen = .analysis
                    }
                }, onShowHistory: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        screen = .history
                    }
                })

            case .history:
                HistoryView(sessions: sessionStore.sessions) { session in
                    let url = session.videoURL
                    let duration = VideoStorage.getDurationSeconds(for: url)
                    analysisDuration = duration > 0 ? duration : 92
                    analysisShots = MockSwingDetector.detectSwings(in: url)
                    analysisVideoURL = url
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        screen = .analysis
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))

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
