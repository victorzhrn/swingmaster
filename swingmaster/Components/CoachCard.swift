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
        GlassContainer(style: .medium, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                // Header with AI Coach label
                HStack {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Text("AI Coach Insight")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Spacer()
                    
                    // Rating badge
                    Text(rating)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.micro)
                        .background(
                            Capsule()
                                .fill(TennisColors.tennisGreen)
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
                            .fill(index < 3 ? TennisColors.tennisGreen : Color.gray.opacity(0.3))
                            .frame(height: 4)
                    }
                }
            }
            .padding(Spacing.cardPadding)
        }
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
