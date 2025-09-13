//
//  MainView.swift
//  swingmaster
//
//  Main dashboard view with session cards and floating action button
//

import SwiftUI
// Design System
import Foundation

struct MainView: View {
    @EnvironmentObject var sessionStore: SessionStore
    let onSelectSession: (Session) -> Void
    @State private var showRecordOptions = false
    
    // Mock data for coach insights
    private let coachInsight = "Your forehand contact point has improved 15% this week. Focus on maintaining shoulder rotation through impact."
    private let userRating = "USTR 3.5 → 4.0"
    private let userName = "Victor"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.large) {
                        // Profile header
                        ProfileHeader(name: userName, rating: userRating)
                            .padding(.horizontal, Spacing.screenMargin)
                            .padding(.top, Spacing.medium)
                        
                        // Coach card
                        CoachCard(rating: userRating, insight: coachInsight)
                            .padding(.horizontal, Spacing.screenMargin)
                        
                        // Sessions section
                        VStack(alignment: .leading, spacing: Spacing.medium) {
                            if !sessionStore.sessions.isEmpty {
                                Text("Recent Sessions")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, Spacing.screenMargin)
                            }
                            
                            if sessionStore.sessions.isEmpty {
                                EmptyStateView()
                                    .padding(.top, Spacing.xxlarge)
                            } else {
                                VStack(spacing: Spacing.medium) {
                                    ForEach(sessionStore.sessions.prefix(10)) { session in
                                        VideoSessionCard(session: session)
                                            .onTapGesture { onSelectSession(session) }
                                    }
                                }
                                .padding(.horizontal, Spacing.screenMargin)
                            }
                        }
                        
                        // Bottom padding for floating button
                        Color.clear.frame(height: 100)
                    }
                    .padding(.vertical, Spacing.medium)
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(UIColor.systemBackground),
                            Color(UIColor.secondarySystemBackground).opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
                .overlay(alignment: .bottomTrailing) {
                    FloatingActionButton(isPressed: $showRecordOptions)
                        .padding(Spacing.large)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}


// MARK: - Subviews

struct ProfileHeader: View {
    let name: String
    let rating: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome back,")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(name)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Text(rating)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(TennisColors.tennisGreen)
                }
                .padding(.top, 2)
            }
            Spacer()
            
            // Profile avatar (solid color)
            TennisAvatar(initial: String(name.prefix(1)), size: 56)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Spacing.large) {
            ZStack {
                GlassContainer(style: .subtle, cornerRadius: 50) {
                    Color.clear.frame(width: 100, height: 100)
                }
                
                Image(systemName: "figure.tennis")
                    .font(.system(size: 48))
                    .foregroundColor(TennisColors.tennisGreen)
            }
            
            VStack(spacing: Spacing.small) {
                Text("Start Your Journey")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Record your first swing to get personalized coaching insights")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.xlarge + Spacing.small)
            }
            
            // Arrow pointing to floating button
            VStack(spacing: Spacing.small) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 20))
                    .foregroundColor(TennisColors.tennisGreen)
                    .opacity(0.6)
                
                Text("Tap to begin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TennisColors.tennisGreen)
                    .opacity(0.6)
            }
            .padding(.top, Spacing.large)
        }
        .padding(.vertical, Spacing.xlarge + Spacing.small)
    }
}

#Preview {
    MainView(onSelectSession: { _ in })
        .environmentObject(SessionStore())
        .preferredColorScheme(.dark)
}
