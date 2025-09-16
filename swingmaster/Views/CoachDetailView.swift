import SwiftUI

struct CoachDetailView: View {
    let insight: CoachInsight
    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                // Unified card: header + content on one surface
                GlassContainer(style: .medium, cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        // Tag badge
                        Text(insight.tag)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, Spacing.micro)
                            .background(
                                Capsule()
                                    .fill(TennisColors.tennisGreen)
                            )

                        // Title
                        Text(insight.issueTitle)
                            .font(.system(size: 28, weight: .bold))
                            .padding(.bottom, Spacing.small)

                        // Subtle divider for separation
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.bottom, Spacing.small)

                        // Markdown content
                        MarkdownContent(markdown: insight.markdownContent)
                    }
                    .padding(Spacing.cardPadding)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.medium)
                
                if let video = insight.videoReference {
                    Button(action: { 
                        openURL(URL(string: "https://www.youtube.com/watch?v=\(video.youtubeId)&t=\(video.timestamp)s")!)
                    }) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 20))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(video.title)
                                    .font(.system(size: 15, weight: .medium))
                                Text("Watch from \(video.timestamp / 60):\(String(format: "%02d", video.timestamp % 60))")
                                    .font(.system(size: 13))
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.white)
                        .padding(16)
                        .background(TennisColors.tennisGreen)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, Spacing.screenMargin)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
    }
}