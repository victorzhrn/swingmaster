import SwiftUI

struct WelcomeCoachCard: View {
    var body: some View {
        GlassContainer(style: .medium, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                // Header
                HStack {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Text("Meet Your AI Coach")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TennisColors.tennisGreen)
                    
                    Spacer()
                    
                    Text("NEW")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.micro)
                        .background(Capsule().fill(TennisColors.tennisGreen))
                }
                
                // Message
                Text("Record your first swing and I'll analyze your technique, track your progress, and give you personalized drills 🎾")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
            }
            .padding(Spacing.cardPadding)
        }
    }
}