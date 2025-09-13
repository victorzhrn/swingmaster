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
                // Background circle (solid tennis yellow)
                Circle()
                    .fill(TennisColors.tennisYellow)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                // Plus icon
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(TennisColors.courtGreen)
                    .rotationEffect(.degrees(isPressed ? 135 : 0))
            }
        }
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        .scaleEffect(isPressed ? 0.92 : 1.0)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        FloatingActionButton(isPressed: .constant(false))
    }
}
