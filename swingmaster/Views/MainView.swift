//
//  MainView.swift
//  swingmaster
//
//  Main dashboard view with session cards and floating action button
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var sessionStore: SessionStore
    let onSelectSession: (Session) -> Void
    
    // Mock data for coach insights
    private let coachInsight = "Your forehand contact point has improved 15% this week. Focus on maintaining shoulder rotation through impact."
    private let userRating = "USTR 3.5 → 4.0"
    private let userName = "Victor"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Profile header
                        ProfileHeader(name: userName, rating: userRating)
                            .padding(.horizontal)
                            .padding(.top, 12)
                        
                        // Coach card
                        CoachCard(rating: userRating, insight: coachInsight)
                            .padding(.horizontal)
                        
                        // Sessions section
                        VStack(alignment: .leading, spacing: 16) {
                            if !sessionStore.sessions.isEmpty {
                                Text("Recent Sessions")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal)
                            }
                            
                            if sessionStore.sessions.isEmpty {
                                EmptyStateView()
                                    .padding(.top, 60)
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(sessionStore.sessions.prefix(10)) { session in
                                        VideoSessionCard(session: session)
                                            .onTapGesture { onSelectSession(session) }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Bottom padding for floating button
                        Color.clear.frame(height: 100)
                    }
                    .padding(.vertical)
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
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    Text(rating)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.top, 2)
            }
            Spacer()
            
            // Profile avatar placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Text(name.prefix(1))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                )
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "figure.tennis")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Start Your Journey")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Record your first swing to get personalized coaching insights")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            
            // Arrow pointing to floating button
            VStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .opacity(0.6)
                
                Text("Tap to begin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue)
                    .opacity(0.6)
            }
            .padding(.top, 20)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    MainView(onSelectSession: { _ in })
        .environmentObject(SessionStore())
        .preferredColorScheme(.dark)
}
