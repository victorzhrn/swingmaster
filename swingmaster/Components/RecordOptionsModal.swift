//
//  RecordOptionsModal.swift
//  swingmaster
//
//  Modal for choosing record or upload action
//

import SwiftUI

struct RecordOptionsModal: View {
    let onRecord: () -> Void
    let onUpload: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GlassContainer(style: .heavy, cornerRadius: 20) {
            VStack(spacing: 0) {
                // Title
                Text("Capture Your Swing")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(.top, Spacing.large)
                    .padding(.bottom, Spacing.large)
                
                // Options
                VStack(spacing: Spacing.medium) {
                    // Record option
                    OptionButton(
                        icon: "camera.fill",
                        title: "Record Now",
                        subtitle: "Use camera to capture your swing",
                        color: TennisColors.clayOrange,
                        action: onRecord
                    )
                    
                    // Upload option
                    OptionButton(
                        icon: "square.and.arrow.up.fill",
                        title: "Upload Video",
                        subtitle: "Choose from your photo library",
                        color: TennisColors.tennisGreen,
                        action: onUpload
                    )
                }
                .padding(.horizontal, Spacing.medium)
                
                // Cancel button
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .padding(.top, Spacing.medium)
                .padding(.horizontal, Spacing.medium)
                
                Spacer()
            }
            .padding(.bottom, Spacing.medium)
        }
        .frame(maxHeight: 340)
    }
}

struct OptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    RecordOptionsModal(
        onRecord: { print("Record") },
        onUpload: { print("Upload") }
    )
    .padding()
    .background(Color.gray.opacity(0.1))
    .preferredColorScheme(.dark)
}
