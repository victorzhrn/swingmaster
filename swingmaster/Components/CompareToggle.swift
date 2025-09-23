import SwiftUI

struct CompareToggle: View {
    @Binding var isComparing: Bool
    @State private var isPressed = false
    @Environment(\.theme) private var theme
    
    var body: some View {
        Button(action: toggleCompare) {
            HStack(spacing: Spacing.micro) { // 4pt spacing
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(labelColor)
                    .symbolRenderingMode(.hierarchical)
                
                Text(buttonText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                
                // Custom switch aligned with design principles
                ZStack {
                    Capsule()
                        .fill(switchBackgroundColor)
                        .frame(width: 44, height: 24)
                    
                    Circle()
                        .fill(switchKnobColor)
                        .frame(width: 20, height: 20)
                        .offset(x: isComparing ? 10 : -10)
                        .animation(
                            theme.useReduceMotion ? .none : 
                            .spring(response: 0.3, dampingFraction: 0.8), // .quick spring
                            value: isComparing
                        )
                }
            }
            .padding(.horizontal, Spacing.small) // 8pt
            .padding(.vertical, 6)
            .frame(height: 44) // Minimum tap target
            .background(
                Capsule()
                    .fill(isComparing ? 
                          TennisColors.tennisGreen.opacity(0.05) : 
                          Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.96 : 1.0) // Design principle: scale(0.96) for buttons
        .accessibilityLabel(Text(buttonText))
        .accessibilityHint(Text("Toggle side-by-side comparison with a pro video"))
        .accessibilityValue(Text(isComparing ? "On" : "Off"))
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) { // .instant timing
                    isPressed = pressing
                }
            },
            perform: { }
        )
    }
    
    private func toggleCompare() {
        withAnimation(theme.useReduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
            isComparing.toggle()
        }
        // Haptic feedback per design principles
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private var labelColor: Color {
        isComparing ? .white.opacity(0.95) : .white.opacity(0.6)
    }
    
    private var switchBackgroundColor: Color {
        isComparing ? 
        TennisColors.tennisGreen.opacity(0.3) : 
        Color.white.opacity(0.1)
    }
    
    private var switchKnobColor: Color {
        isComparing ? 
        TennisColors.tennisGreen : 
        Color.white.opacity(0.6)
    }
    
    private var buttonText: String {
        isComparing ? "Exit Pro Compare" : "Compare vs Pro"
    }
}