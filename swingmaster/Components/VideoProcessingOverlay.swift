//
//  VideoProcessingOverlay.swift
//  swingmaster
//
//  Shows inline processing status on video cards
//

import SwiftUI

struct VideoProcessingOverlay: View {
    let status: Session.ProcessingStatus
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.3))
            
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
                
                Text(status.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                
                if let progress = extractProgress() {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(.white)
                        .frame(width: 100)
                        .scaleEffect(x: 1, y: 0.5)
                }
            }
            .padding(16)
        }
        .cornerRadius(16)
    }
    
    private func extractProgress() -> Double? {
        switch status {
        case .extractingPoses(let progress):
            return Double(progress)
        case .validatingSwings(let current, let total):
            return Double(current) / Double(max(1, total))
        case .analyzingSwings(let current, let total):
            return Double(current) / Double(max(1, total))
        default:
            return nil
        }
    }
}

/// Overlay displayed when a session's video processing fails.
/// Shows a succinct error message and a retry action.
struct ProcessingErrorOverlay: View {
    let error: String
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
            
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.red)
                
                Text("Processing failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 200)
                
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(16)
        }
        .cornerRadius(16)
    }
}