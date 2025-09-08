//
//  ContentView.swift
//  swingmaster
//
//  Created by ruinan zhang on 2025/9/6.
//

import SwiftUI

struct ContentView: View {
    private enum Screen {
        case camera
        case history
    }

    @State private var screen: Screen = .camera

    var body: some View {
        ZStack {
            switch screen {
            case .camera:
                CameraView(onRecorded: { _ in
                    // TODO: Navigate to AnalysisView with recorded URL in later phase
                }, onShowHistory: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        screen = .history
                    }
                })

            case .history:
                HistoryView { _ in
                    // TODO: push to AnalysisView in Phase 3
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if screen == .history {
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                screen = .camera
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
