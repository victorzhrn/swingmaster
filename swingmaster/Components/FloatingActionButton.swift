//
//  FloatingActionButton.swift
//  swingmaster
//
//  Floating action button for recording/uploading
//

import SwiftUI

struct FloatingActionButton: View {
    @Binding var isPressed: Bool
    @State private var isAnimating = false
    @State private var pulseAnimation = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = true
            }
            
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }) {
            ZStack {
                // Pulse effect
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.5)
                
                // Background circle with gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue,
                                Color.blue.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isPressed ? 135 : 0))
            }
        }
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
        .shadow(color: Color.blue.opacity(0.4), radius: 5, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                pulseAnimation = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        FloatingActionButton(isPressed: .constant(false))
    }
}
