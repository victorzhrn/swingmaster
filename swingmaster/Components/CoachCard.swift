//
//  CoachCard.swift
//  swingmaster
//
//  Minimal coach insight card for MVP
//

import SwiftUI

struct CoachCard: View {
    let category: String
    let insight: String
    let issueTitle: String
    var showPageIndicator: Bool = false
    var currentPage: Int = 0
    var pageCount: Int = 1
    
    var body: some View {
        GlassContainer(style: .medium, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                // Header with issue title
                HStack {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Text(issueTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Spacer()
                    
                    // Category badge with consistent color
                    Text(category)
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
                
                // Integrated page indicator - full width
                if showPageIndicator {
                    PageIndicator(
                        currentPage: currentPage,
                        pageCount: pageCount,
                        style: .line
                    )
                    .padding(.top, Spacing.micro)
                }
            }
            .padding(Spacing.cardPadding)
        }
    }
}

#Preview {
    CoachCard(
        category: "Forhand",
        insight: "Your forehand contact point has improved 15% this week. Focus on maintaining shoulder rotation through impact.",
        issueTitle: "Late Contact Point"
    )
    .padding()
    .preferredColorScheme(.dark)
}
