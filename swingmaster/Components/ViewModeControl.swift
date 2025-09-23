import SwiftUI

/// Unified view mode control that selects between trajectory views and skeleton.
/// Replaces the old TrajectorySelector and inline ViewControlsPanel.
struct ViewModeControl: View {
    @Binding var enabledTrajectories: Set<TrajectoryType>
    @Binding var showSkeleton: Bool
    @Binding var skeletonOnly: Bool

    @State private var isMenuOpen: Bool = false
    @State private var selectedOption: ViewOption = .wrist
    @AppStorage("lastSelectedTrajectory") private var lastSelectedTrajectory: String = "wrist"

    enum ViewOption: String, CaseIterable {
        case racket = "Racket Path"
        case wrist = "Wrist Path"
        case skeleton = "Skeleton"
        case skeletonOnly = "Skeleton Only"
        case off = "Off"

        var icon: String {
            switch self {
            case .racket: return "tennis.racket"
            case .wrist: return "hand.wave"
            case .skeleton: return "figure.walk"
            case .skeletonOnly: return "eye.slash"
            case .off: return "slash.circle"
            }
        }
    }

    var body: some View {
        Button(action: { isMenuOpen.toggle() }) {
            HStack(spacing: Spacing.micro) { // 4pt spacing to match CompareToggle
                Image(systemName: "eye")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .symbolRenderingMode(.hierarchical)
                Text("View")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Text(selectedOption.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
        }
        .contentShape(Rectangle())
        .overlay(menuView, alignment: .top)
        .accessibilityLabel(Text("View mode"))
        .accessibilityValue(Text(selectedOption.rawValue))
        .onAppear { syncFromBindings() }
    }

    @ViewBuilder
    private var menuView: some View {
        if isMenuOpen {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ViewOption.allCases, id: \.self) { option in
                    Button(action: { select(option) }) {
                        HStack(spacing: 8) {
                            Image(systemName: option.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 18)
                            Text(option.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .opacity(selectedOption == option ? 1 : 0)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                    }
                    if option != ViewOption.allCases.last {
                        Divider()
                            .background(Color.white.opacity(0.15))
                    }
                }
            }
            .frame(minWidth: 200)
            .background(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .cornerRadius(12)
            .offset(y: -160)
        }
    }

    private func select(_ option: ViewOption) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedOption = option
            lastSelectedTrajectory = option.storageKey
            applyToBindings(option)
            isMenuOpen = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyToBindings(_ option: ViewOption) {
        switch option {
        case .skeleton:
            showSkeleton = true
            enabledTrajectories.removeAll()
            skeletonOnly = false
        case .skeletonOnly:
            showSkeleton = true
            enabledTrajectories.removeAll()
            skeletonOnly = true
        case .off:
            showSkeleton = false
            enabledTrajectories.removeAll()
            skeletonOnly = false
        case .racket:
            showSkeleton = false
            enabledTrajectories = [.racketCenter]
            skeletonOnly = false
        case .wrist:
            showSkeleton = false
            enabledTrajectories = [.rightWrist]
            skeletonOnly = false
        }
    }

    private func syncFromBindings() {
        if showSkeleton {
            selectedOption = skeletonOnly ? .skeletonOnly : .skeleton
        } else if enabledTrajectories.contains(.racketCenter) {
            selectedOption = .racket
        } else if enabledTrajectories.contains(.rightWrist) {
            selectedOption = .wrist
        } else if let stored = ViewOption(storageKey: lastSelectedTrajectory) {
            selectedOption = stored
            applyToBindings(stored)
        } else {
            selectedOption = .wrist
            applyToBindings(.wrist)
        }
    }
}

private extension ViewModeControl.ViewOption {
    var storageKey: String {
        switch self {
        case .racket: return "racket"
        case .wrist: return "wrist"
        case .skeleton: return "skeleton"
        case .skeletonOnly: return "skeletonOnly"
        case .off: return "off"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "racket": self = .racket
        case "wrist": self = .wrist
        case "skeleton": self = .skeleton
        case "skeletonOnly": self = .skeletonOnly
        case "off": self = .off
        default: return nil
        }
    }
}


