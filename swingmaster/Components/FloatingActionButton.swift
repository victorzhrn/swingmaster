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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("Session")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(TennisColors.tennisGreen)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 5)
        .buttonStyle(PressableStyle())
    }
}

/// ButtonStyle that provides tactile press feedback via a transient scale animation.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        FloatingActionButton(isPressed: .constant(false))
    }
}
