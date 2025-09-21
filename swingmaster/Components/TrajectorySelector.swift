//
//  TrajectorySelector.swift
//  swingmaster
//
//  Segmented control trajectory selector for single trajectory visualization.
//

import SwiftUI
import UIKit

struct TrajectorySelector: View {
    @Binding var enabledTrajectories: Set<TrajectoryType>
    @Binding var isComparing: Bool
    
    // Store the last selected trajectory for better UX
    @AppStorage("lastSelectedTrajectory") private var lastSelectedTrajectory: String = "racket"
    
    // Single selection state
    @State private var selectedOption: TrajectoryOption = .racket
    
    // Trajectory options for segmented control
    enum TrajectoryOption: String, CaseIterable {
        case racket = "Racket"
        case wrist = "Wrist"
        case off = "Off"
        
        var trajectoryType: TrajectoryType? {
            switch self {
            case .racket: return .racketCenter
            case .wrist: return .rightWrist
            case .off: return nil
            }
        }
        
        var color: Color {
            // Use a consistent tennis green for all trajectory types
            // Creates a more cohesive, professional look
            switch self {
            case .racket, .wrist: 
                return TennisColors.tennisGreen
            case .off: 
                return .clear
            }
        }
    }
    
    var body: some View {
        HStack(spacing: Spacing.small) { // Use design token: 8pt
            // Left: Compressed trajectory selector
            HStack(spacing: 2) {
                ForEach(TrajectoryOption.allCases, id: \.self) { option in
                    SegmentButton(
                        title: option.rawValue,
                        isSelected: selectedOption == option,
                        color: option.color,
                        action: { selectOption(option) }
                    )
                }
            }
            .frame(maxWidth: 160) // Reduced to fit compare toggle
            
            Spacer()
            
            // Right: Compare toggle
            CompareToggle(isComparing: $isComparing)
        }
        .padding(.horizontal, Spacing.micro) // 4pt
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.05))
        )
        .onAppear {
            initializeSelection()
        }
    }
    
    private func initializeSelection() {
        // Sync with the current binding state first
        // If enabledTrajectories already has a selection, use that
        if !enabledTrajectories.isEmpty {
            // Find which option matches the current enabled trajectories
            for option in TrajectoryOption.allCases {
                if let type = option.trajectoryType, enabledTrajectories.contains(type) {
                    selectedOption = option
                    lastSelectedTrajectory = option.rawValue.lowercased()
                    return // Don't update the binding, it's already set
                }
            }
            // If no trajectories enabled, set to off
            if enabledTrajectories.isEmpty {
                selectedOption = .off
                lastSelectedTrajectory = "off"
                return // Don't update the binding
            }
        } else {
            // No trajectories enabled, load saved preference or default to racket
            if let savedOption = TrajectoryOption(rawValue: lastSelectedTrajectory.capitalized) {
                selectedOption = savedOption
            } else {
                selectedOption = .racket
            }
            // Apply the selection to the binding
            updateEnabledTrajectories(for: selectedOption)
        }
    }
    
    private func selectOption(_ option: TrajectoryOption) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { // Standard .quick spring
            selectedOption = option
            lastSelectedTrajectory = option.rawValue.lowercased()
            updateEnabledTrajectories(for: option)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func updateEnabledTrajectories(for option: TrajectoryOption) {
        // Clear all trajectories first
        enabledTrajectories.removeAll()
        
        // Add the selected trajectory if not "off"
        if let trajectoryType = option.trajectoryType {
            enabledTrajectories.insert(trajectoryType)
        }
    }
}

// Segmented control button component
struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            isPressed = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 32) // Smaller height for pill design
                .background(backgroundView)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.9), value: isPressed)
    }
    
    private var textColor: Color {
        if isSelected {
            return .white.opacity(0.95) // Consistent selected opacity
        } else {
            return .white.opacity(0.6) // Consistent default opacity
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            // Unified selection state with tennis green
            Capsule()
                .fill(TennisColors.tennisGreen.opacity(title == "Off" ? 0.1 : 0.15))
        } else {
            Color.clear
        }
    }
}


