//
//  TimelineStripEnhanced.swift
//  swingmaster
//
//  Simplified timeline with direct manipulation. Markers expand in place to show segments.
//  Cleaner visual design following iOS design principles.
//

import SwiftUI
import UIKit

struct TimelineStripEnhanced: View {
    let duration: Double
    let shots: [Shot]
    @Binding var selectedShotID: Shot.ID?
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool
    
    /// Callback when user wants to play a specific segment
    var onPlaySegment: ((Shot) -> Void)?
    
    /// State for animation
    @State private var expandedShotID: Shot.ID?
    @State private var dragLocation: CGPoint? = nil
    @State private var showNavigationHint: Bool = false
    @Namespace private var markerNamespace
    @Environment(\.colorScheme) private var colorScheme
    
    private let markerSize: CGFloat = 12
    private let expandedHeight: CGFloat = 32
    private let bandHeight: CGFloat = 48  // Reduced from 56
    
    var body: some View {
        HStack(spacing: 0) {
            // Compact prev button (integrated into timeline edge)
            Button(action: navigatePrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(canNavigatePrev ? .white.opacity(0.95) : .white.opacity(0.3))
                    .frame(width: 32, height: bandHeight)
                    .contentShape(Rectangle())
            }
            .disabled(!canNavigatePrev)
            .buttonStyle(PlainButtonStyle())
            
            // Timeline content
            GeometryReader { geo in
                ScrollViewReader { scrollProxy in
                    timelineContent(geometry: geo)
                        .onChange(of: selectedShotID) { oldValue, newValue in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { // Standard .quick spring
                                expandedShotID = newValue
                            }
                            if let id = newValue {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scrollProxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                }
            }
            
            // Compact next button (integrated into timeline edge)
            Button(action: navigateNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(canNavigateNext ? .white.opacity(0.95) : .white.opacity(0.3))
                    .frame(width: 32, height: bandHeight)
                    .contentShape(Rectangle())
            }
            .disabled(!canNavigateNext)
            .buttonStyle(PlainButtonStyle())
        }
        .frame(height: bandHeight)
        .onAppear {
            // Show navigation hint for crowded timelines
            if shouldShowNavigationHint {
                showNavigationHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showNavigationHint = false
                    }
                }
            }
        }
        .overlay(navigationHintOverlay, alignment: .top)
    }
    
    // MARK: - Main Timeline Content
    
    @ViewBuilder
    private func timelineContent(geometry geo: GeometryProxy) -> some View {
        ZStack(alignment: .leading) {
            // Baseline track with subtle visibility
            Rectangle()
                .fill(Color.white.opacity(0.05)) // Subtle track for both light and dark
                .frame(height: 2)
                .frame(maxWidth: .infinity)
            
            // Markers layer
            ForEach(shots) { shot in
                shotMarker(shot: shot, width: geo.size.width)
                    .id(shot.id)
            }
            
            // Playhead indicator
            if isPlaying {
                playhead(width: geo.size.width)
            }
        }
        .frame(height: bandHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragLocation = value.location
                    // Magnetic snapping during drag
                    if let nearest = nearestShot(atX: value.location.x, totalWidth: geo.size.width) {
                        let distance = abs(xPosition(for: nearest.time, width: geo.size.width) - value.location.x)
                        if distance < 30 { // Snap radius
                            select(nearest)
                        }
                    }
                }
                .onEnded { value in
                    dragLocation = nil
                    if let nearest = nearestShot(atX: value.location.x, totalWidth: geo.size.width) {
                        select(nearest)
                        // Don't auto-play on drag, only on tap
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot timeline")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction: direction)
        }
    }
    
    // MARK: - Shot Marker (Unified Design)
    
    @ViewBuilder
    private func shotMarker(shot: Shot, width: CGFloat) -> some View {
        let isSelected = shot.id == selectedShotID
        let isExpanded = shot.id == expandedShotID
        let xPos = xPosition(for: shot.time, width: width)
        
        // Unified marker that expands in place
        if isExpanded && isSelected {
            // Expanded segment view
            expandedSegmentView(for: shot, width: width)
                .position(x: xPos, y: bandHeight / 2)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
        } else {
            // Compact dot marker
            compactMarkerView(for: shot, selected: isSelected)
                .position(x: xPos, y: bandHeight / 2)
        }
    }
    
    @ViewBuilder
    private func compactMarkerView(for shot: Shot, selected: Bool) -> some View {
        Button(action: {
            select(shot)
            onPlaySegment?(shot)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            ZStack {
                Circle()
                    .fill(TennisColors.tennisGreen.opacity(selected ? 0.9 : 0.6))
                    .frame(width: markerSize, height: markerSize)
                
                // Type abbreviation inside dot
                Text(shot.type.shortLabel)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .scaleEffect(selected ? 1.2 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected) // Standard .quick spring
    }
    
    @ViewBuilder
    private func expandedSegmentView(for shot: Shot, width: CGFloat) -> some View {
        let startX = xPosition(for: shot.startTime, width: width)
        let endX = xPosition(for: shot.endTime, width: width)
        let segmentWidth = max(60, endX - startX)  // Minimum width for readability
        
        Button(action: {
            // Clicking the expanded segment replays that shot
            onPlaySegment?(shot)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            ZStack {
                // Expanded background
                RoundedRectangle(cornerRadius: expandedHeight / 2)
                    .fill(TennisColors.tennisGreen)
                    .frame(width: segmentWidth, height: expandedHeight)
                
                // Progress indicator during playback
                if isPlaying && currentTime >= shot.startTime && currentTime <= shot.endTime {
                    let progress = (currentTime - shot.startTime) / shot.duration
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: expandedHeight / 2)
                            .fill(TennisColors.tennisYellow.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                    .frame(width: segmentWidth - 4, height: expandedHeight - 4)
                    .clipShape(RoundedRectangle(cornerRadius: (expandedHeight - 4) / 2))
                }
                
                // Content - show play/replay icon based on playback state
                HStack(spacing: 6) {
                    Image(systemName: isPlaying && currentTime >= shot.startTime && currentTime <= shot.endTime ? "pause.fill" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text(shot.type.shortLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    
                    Text(String(format: "%.1fs", shot.duration))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .opacity(0.9)
                }
                .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Playhead (Simplified)
    
    @ViewBuilder
    private func playhead(width: CGFloat) -> some View {
        let xPos = xPosition(for: currentTime, width: width)
        
        Rectangle()
            .fill(TennisColors.tennisYellow)
            .frame(width: 2, height: bandHeight - 8)
            .position(x: xPos, y: bandHeight / 2)
            .allowsHitTesting(false)
            .animation(.linear(duration: 0.1), value: currentTime)
    }
    
    // MARK: - Helper Methods
    
    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clamped = max(0, min(time, duration))
        // Use full width for better space utilization
        return CGFloat(clamped / duration) * width
    }
    
    private func nearestShot(atX x: CGFloat, totalWidth: CGFloat) -> Shot? {
        guard !shots.isEmpty else { return nil }
        let pairs = shots.map { shot -> (Shot, CGFloat) in
            let pos = xPosition(for: shot.time, width: totalWidth)
            return (shot, abs(pos - x))
        }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }
    
    private func select(_ shot: Shot) {
        if selectedShotID != shot.id {
            selectedShotID = shot.id
            currentTime = shot.time
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            // Announce selection for VoiceOver
            if UIAccessibility.isVoiceOverRunning {
                let announcement = "\(shot.type.accessibleName) selected"
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        }
    }
    
    private func adjustSelection(direction: AccessibilityAdjustmentDirection) {
        guard let currentIndex = shots.firstIndex(where: { $0.id == selectedShotID }) else {
            if let first = shots.first { select(first) }
            return
        }
        switch direction {
        case .increment:
            let next = Swift.min(currentIndex + 1, shots.count - 1)
            select(shots[next])
        case .decrement:
            let prev = Swift.max(currentIndex - 1, 0)
            select(shots[prev])
        @unknown default:
            break
        }
    }
    
    private var accessibilityValue: String {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else {
            return "No shot selected"
        }
        let shot = shots[idx]
        return "Shot \(idx + 1) of \(shots.count), \(shot.type.accessibleName)"
    }
    
    // MARK: - Navigation Helpers
    
    private func navigatePrev() {
        guard let currentIndex = shots.firstIndex(where: { $0.id == selectedShotID }),
              currentIndex > 0 else { return }
        
        let prevShot = shots[currentIndex - 1]
        select(prevShot)
        onPlaySegment?(prevShot)
    }
    
    private func navigateNext() {
        guard let currentIndex = shots.firstIndex(where: { $0.id == selectedShotID }),
              currentIndex < shots.count - 1 else { return }
        
        let nextShot = shots[currentIndex + 1]
        select(nextShot)
        onPlaySegment?(nextShot)
    }
    
    private var canNavigatePrev: Bool {
        guard let id = selectedShotID,
              let idx = shots.firstIndex(where: { $0.id == id }) else { return false }
        return idx > 0
    }
    
    private var canNavigateNext: Bool {
        guard let id = selectedShotID,
              let idx = shots.firstIndex(where: { $0.id == id }) else { return false }
        return idx < shots.count - 1
    }
    
    private var shouldShowNavigationHint: Bool {
        // Show hint if average spacing between markers is less than 40pt
        guard shots.count > 1, duration > 0 else { return false }
        let averageSpacing = UIScreen.main.bounds.width / CGFloat(shots.count)
        return averageSpacing < 40
    }
    
    @ViewBuilder
    private var navigationHintOverlay: some View {
        if showNavigationHint {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.chevron.right")
                    .font(.system(size: 10))
                Text("Use arrows for precise navigation")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.9))
            )
            .offset(y: -30)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Preview

#Preview("Timeline with Navigation") {
    struct PreviewWrapper: View {
        @State private var shots = Array<Shot>.sampleShots(duration: 90)
        @State private var denseShotsExample: [Shot] = {
            let duration: Double = 30
            let count = 15
            return (0..<count).map { i in
                let t = (Double(i) + 0.5) / Double(count) * duration
                let type: ShotType = [ShotType.forehand, .backhand, .serve][i % 3]
                let start = max(0, t - 0.45)
                let end = min(duration, t + 0.45)
                return Shot(time: t, type: type, issue: "", startTime: start, endTime: end)
            }
        }() // Dense timeline
        @State private var selectedID: UUID?
        @State private var denseSelectedID: UUID?
        @State private var currentTime: Double = 0
        @State private var isPlaying: Bool = false
        
        var body: some View {
            VStack(spacing: 32) {
                // Dense timeline example (shows navigation controls)
                VStack(spacing: 16) {
                    Text("Dense Timeline (15 shots in 30s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TimelineStripEnhanced(
                        duration: 30,
                        shots: denseShotsExample,
                        selectedShotID: $denseSelectedID,
                        currentTime: $currentTime,
                        isPlaying: $isPlaying
                    ) { shot in
                        currentTime = shot.startTime
                        // Auto-play disabled for demo
                    }
                    .background(Color(hex: "#1C1C1E").opacity(0.95))
                    
                    if let id = denseSelectedID,
                       let shot = denseShotsExample.first(where: { $0.id == id }),
                       let idx = denseShotsExample.firstIndex(where: { $0.id == id }) {
                        Text("Shot \(idx + 1): \(shot.type.rawValue)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .preferredColorScheme(.dark)
                .padding()
                
                // Normal timeline example
                VStack(spacing: 16) {
                    Text("Normal Timeline (6 shots in 90s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TimelineStripEnhanced(
                        duration: 90,
                        shots: shots,
                        selectedShotID: $selectedID,
                        currentTime: $currentTime,
                        isPlaying: $isPlaying
                    ) { shot in
                        currentTime = shot.startTime
                        isPlaying = true
                    }
                    .background(Color.white.opacity(0.95))
                }
                .preferredColorScheme(.light)
                .padding()
                
                // Instructions
                VStack(spacing: 8) {
                    Text("Navigation Methods:")
                        .font(.caption.bold())
                    Text("• Tap/drag timeline to select shots")
                        .font(.caption)
                    Text("• Use arrow buttons for precise navigation")
                        .font(.caption)
                    Text("• Arrows appear when shots are close together")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding()
            }
            .background(Color(UIColor.systemBackground))
            .onAppear {
                selectedID = shots.first?.id
                denseSelectedID = denseShotsExample.first?.id
            }
        }
    }
    
    return PreviewWrapper()
}
