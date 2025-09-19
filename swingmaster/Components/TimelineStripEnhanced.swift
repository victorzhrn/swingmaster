//
//  TimelineStripEnhanced.swift
//  swingmaster
//
//  Context-aware timeline that shows dots by default and expands selected shot
//  into a segment showing its duration. Supports segment playback.
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
    
    /// Optional navigation callbacks for prev/next controls at edges
    var onPrev: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil
    
    /// State for animation
    @State private var expandedShotID: Shot.ID?
    @State private var pulsingMarkerID: Shot.ID?
    @Namespace private var markerNamespace
    @Environment(\.colorScheme) private var colorScheme
    
    private let minInteractiveRadius: CGFloat = 22  // Increased for 44pt touch target
    private let bandHeight: CGFloat = 56
    
    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scrollProxy in
                // For short videos, avoid nested scrolling (fix scroll bug)
                Group {
                    if duration < 120 {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 20)
                            timelineContent(geometry: geo)
                                .id("timeline-content")
                            Color.clear.frame(width: 20)
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 20)
                                timelineContent(geometry: geo)
                                    .id("timeline-content")
                                Color.clear.frame(width: 20)
                            }
                        }
                    }
                }
                .onChange(of: selectedShotID) { oldValue, newValue in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        expandedShotID = newValue
                        pulsingMarkerID = newValue
                    }
                    if let id = newValue {
                        withAnimation(.spring(response: 0.3)) {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                        // Stop pulsing after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            if pulsingMarkerID == id {
                                withAnimation {
                                    pulsingMarkerID = nil
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: bandHeight)
    }
    
    // MARK: - Main Timeline Content
    
    @ViewBuilder
    private func timelineContent(geometry geo: GeometryProxy) -> some View {
        ZStack(alignment: .leading) {
                // Timeline content (padded inside)
                Group {
                    // Baseline axis
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12))
                        .frame(height: 3)
                        .offset(y: -2)

                    // Markers and segments
                    ForEach(shots) { shot in
                        shotMarkerOrSegment(shot: shot, width: geo.size.width, height: geo.size.height)
                            .id(shot.id)
                    }

                    // Playhead indicator
                    playheadIfNeeded(width: geo.size.width, height: geo.size.height)
                }
                .padding(.horizontal, 12)

                // Edge navigation buttons (no horizontal padding to sit at ends)
                HStack {
                    Button(action: { onPrev?(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(TennisColors.courtGreen)
                            .opacity(canDecrement ? 1.0 : 0.4)
                    }
                    .frame(width: 44, height: bandHeight)
                    .contentShape(Rectangle())
                    .disabled(!canDecrement)
                    .accessibilityLabel("Previous shot")
                    .accessibilityHint(canDecrement ? "Go to previous swing" : "Already at first swing")
                    
                    Spacer()
                    
                    Button(action: { onNext?(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(TennisColors.courtGreen)
                            .opacity(canIncrement ? 1.0 : 0.4)
                    }
                    .frame(width: 44, height: bandHeight)
                    .contentShape(Rectangle())
                    .disabled(!canIncrement)
                    .accessibilityLabel("Next shot")
                    .accessibilityHint(canIncrement ? "Go to next swing" : "Already at last swing")
                }
                .padding(.horizontal, 0)
                .frame(height: bandHeight)
                .allowsHitTesting(true)
            }
            
        
        .frame(height: bandHeight)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    let x = value.location.x
                    if let nearest = nearestShot(atX: x, totalWidth: geo.size.width) {
                        select(nearest)
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
    
    @ViewBuilder
    private func shotMarkerOrSegment(shot: Shot, width: CGFloat, height: CGFloat) -> some View {
        let isSelected = shot.id == selectedShotID
        let isExpanded = shot.id == expandedShotID
        
        ZStack {
            // Always show the marker dot
            let xPos = xPosition(for: shot.time, width: width)
            markerView(for: shot, selected: isSelected)
                .position(x: max(44, min(width - 44, xPos)), y: height / 2)
                .contentShape(Rectangle().inset(by: -minInteractiveRadius))
                .onTapGesture {
                    select(shot)
                    // Auto-play segment when marker selected
                    onPlaySegment?(shot)
                }
            
            // Show segment ABOVE timeline (not replacing dot)
            if isExpanded && isSelected {
                segmentView(for: shot, width: width)
                    .offset(y: -20)  // Position above the timeline
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
    
    @ViewBuilder
    private func playheadIfNeeded(width: CGFloat, height: CGFloat) -> some View {
        if isPlaying,
           let selected = shots.first(where: { $0.id == selectedShotID }),
           currentTime >= selected.startTime,
           currentTime <= selected.endTime {
            let xPos = xPosition(for: currentTime, width: width)
            playheadView()
                .position(x: xPos, y: height / 2)
                .allowsHitTesting(false)
        }
    }
    
    // MARK: - Segment View (Expanded State)
    
    @ViewBuilder
    private func segmentView(for shot: Shot, width: CGFloat) -> some View {
        let startX = xPosition(for: shot.startTime, width: width)
        let endX = xPosition(for: shot.endTime, width: width)
        let segmentWidth = max(44, endX - startX)  // Minimum width for visibility
        
        ZStack {
            // Segment bar background
            RoundedRectangle(cornerRadius: 8)
                .fill(markerColor(for: shot).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(markerColor(for: shot), lineWidth: 2)
                )
                .frame(width: segmentWidth, height: 24)
            
            // Progress fill animation during playback
            if isPlaying && currentTime >= shot.startTime && currentTime <= shot.endTime {
                let progress = (currentTime - shot.startTime) / shot.duration
                GeometryReader { innerGeo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [markerColor(for: shot), markerColor(for: shot).opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: innerGeo.size.width * CGFloat(progress))
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .frame(width: segmentWidth - 4, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // Label
            HStack(spacing: 4) {
                if !isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                }
                Text(shot.type.shortLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
        }
        .position(x: (startX + endX) / 2, y: bandHeight / 2)
        .onTapGesture {
            // Play this segment
            onPlaySegment?(shot)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
    
    // MARK: - Marker View (Default State)
    
    @ViewBuilder
    private func markerView(for shot: Shot, selected: Bool) -> some View {
        let isPulsing = shot.id == pulsingMarkerID
        let baseSize: CGFloat = selected ? 20 : 12
        
        ZStack {
            // Pulse animation ring
            if isPulsing {
                Circle()
                    .stroke(markerColor(for: shot), lineWidth: 2)
                    .frame(width: baseSize + 20, height: baseSize + 20)
                    .opacity(0)
                    .modifier(PulseAnimation())
            }
            
            Circle()
                .fill(markerColor(for: shot).opacity(0.9))
                .frame(width: baseSize, height: baseSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(selected ? 0.9 : 0.6), lineWidth: selected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            
            if selected {
                Text(shot.type.shortLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .frame(minWidth: minInteractiveRadius * 2, minHeight: minInteractiveRadius * 2)
        .scaleEffect(selected ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        .accessibilityLabel("\(shot.type.accessibleName), score \(String(format: "%.1f", shot.score))")
        .accessibilityHint("Double tap to play this segment")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    
    // Pulse animation modifier
    struct PulseAnimation: ViewModifier {
        @State private var scale: CGFloat = 1.0
        @State private var opacity: Double = 0.6
        
        func body(content: Content) -> some View {
            content
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(
                        .easeOut(duration: 1.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        scale = 1.5
                        opacity = 0
                    }
                }
        }
    }

    private func markerColor(for shot: Shot) -> Color {
        // Color-code by shot quality
        if shot.score >= 7.5 { return .shotExcellent }
        if shot.score >= 5.5 { return .shotGood }
        return .shotNeedsWork
    }
    
    // MARK: - Playhead View
    
    @ViewBuilder
    private func playheadView() -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 8, height: 8)
                .shadow(color: (colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.2)), radius: 2)
            
            Rectangle()
                .fill((colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.6)))
                .frame(width: 2, height: 20)
        }
    }
    
    // MARK: - Helper Methods
    
    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clamped = max(0, min(time, duration))
        // Use content width minus 88 with 44pt padding on both sides
        let contentWidth = max(1, width - 88)
        return CGFloat(clamped / duration) * contentWidth + 44
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
        selectedShotID = shot.id
        currentTime = shot.time
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Announce selection for VoiceOver
        if UIAccessibility.isVoiceOverRunning {
            let announcement = "\(shot.type.accessibleName) selected, score \(String(format: "%.1f", shot.score))"
            UIAccessibility.post(notification: .announcement, argument: announcement)
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
    
    private var canDecrement: Bool {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else { return false }
        return idx > 0
    }
    
    private var canIncrement: Bool {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else { return false }
        return idx < shots.count - 1
    }
}

// MARK: - Preview

#Preview("Enhanced Timeline") {
    struct PreviewWrapper: View {
        @State private var shots = Array<Shot>.sampleShots(duration: 90)
        @State private var selectedID: UUID?
        @State private var currentTime: Double = 0
        @State private var isPlaying: Bool = false
        
        var body: some View {
            VStack(spacing: 20) {
                TimelineStripEnhanced(
                    duration: 90,
                    shots: shots,
                    selectedShotID: $selectedID,
                    currentTime: $currentTime,
                    isPlaying: $isPlaying
                ) { shot in
                    // Start playing the segment
                    currentTime = shot.startTime
                    isPlaying = true
                }
                .padding()
                
                HStack {
                    Button(isPlaying ? "Pause" : "Play") {
                        isPlaying.toggle()
                    }
                    Text("Time: \(String(format: "%.1f", currentTime))s")
                        .font(.system(.body, design: .monospaced))
                }
                .padding()
            }
            .preferredColorScheme(.dark)
            .background(Color.black)
            .onAppear {
                selectedID = shots.first?.id
            }
        }
    }
    
    return PreviewWrapper()
}
