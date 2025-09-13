//
//  CoachCard.swift
//  swingmaster
//
//  Minimal coach insight card for MVP
//

import SwiftUI

struct CoachCard: View {
    let rating: String
    let insight: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with AI Coach label
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("AI Coach Insight")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                
                Spacer()
                
                // Rating badge
                Text(rating)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
            }
            
            // Insight text
            Text(insight)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            // Visual indicator (simplified progress bar)
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < 3 ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

#Preview {
    CoachCard(
        rating: "USTR 3.5 → 4.0",
        insight: "Your forehand contact point has improved 15% this week. Focus on maintaining shoulder rotation through impact."
    )
    .padding()
    .preferredColorScheme(.dark)
}
