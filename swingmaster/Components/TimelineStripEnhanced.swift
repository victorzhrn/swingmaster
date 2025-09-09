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
    let shots: [MockShot]
    @Binding var selectedShotID: MockShot.ID?
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool
    
    /// Callback when user wants to play a specific segment
    var onPlaySegment: ((MockShot) -> Void)?
    
    /// State for animation
    @State private var expandedShotID: MockShot.ID?
    @Namespace private var markerNamespace
    
    private let minInteractiveRadius: CGFloat = 16
    private let bandHeight: CGFloat = 56
    
    var body: some View {
        GeometryReader { geo in
            timelineContent(geometry: geo)
        }
        .frame(height: bandHeight)
        .onChange(of: selectedShotID) { oldValue, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                expandedShotID = newValue
            }
        }
    }
    
    // MARK: - Main Timeline Content
    
    @ViewBuilder
    private func timelineContent(geometry geo: GeometryProxy) -> some View {
        ZStack {
            // Glass background strip
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            
            // Timeline content
            ZStack(alignment: .leading) {
                // Baseline axis
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 3)
                    .offset(y: -2)
                
                // Markers and segments
                ForEach(shots) { shot in
                    shotMarkerOrSegment(shot: shot, width: geo.size.width, height: geo.size.height)
                }
                
                // Playhead indicator
                playheadIfNeeded(width: geo.size.width, height: geo.size.height)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: bandHeight)
        .gesture(
            DragGesture(minimumDistance: 0)
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
    private func shotMarkerOrSegment(shot: MockShot, width: CGFloat, height: CGFloat) -> some View {
        let isSelected = shot.id == selectedShotID
        let isExpanded = shot.id == expandedShotID
        
        if isExpanded && isSelected {
            // Show as segment when selected
            segmentView(for: shot, width: width)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
        } else {
            // Show as dot when not selected
            let xPos = xPosition(for: shot.time, width: width)
            markerView(for: shot, selected: isSelected)
                .position(x: xPos, y: height / 2)
                .contentShape(Rectangle().inset(by: -minInteractiveRadius))
                .onTapGesture {
                    select(shot)
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
    private func segmentView(for shot: MockShot, width: CGFloat) -> some View {
        let startX = xPosition(for: shot.startTime, width: width)
        let endX = xPosition(for: shot.endTime, width: width)
        let segmentWidth = max(44, endX - startX)  // Minimum width for visibility
        
        ZStack {
            // Segment bar
            RoundedRectangle(cornerRadius: 8)
                .fill(shot.type.accentColor.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(shot.type.accentColor, lineWidth: 2)
                )
                .frame(width: segmentWidth, height: 24)
            
            // Progress fill if playing
            if isPlaying && currentTime >= shot.startTime && currentTime <= shot.endTime {
                let progress = (currentTime - shot.startTime) / shot.duration
                GeometryReader { innerGeo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(shot.type.accentColor.opacity(0.6))
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
    private func markerView(for shot: MockShot, selected: Bool) -> some View {
        let baseSize: CGFloat = selected ? 20 : 12
        ZStack {
            Circle()
                .fill(shot.type.accentColor.opacity(0.9))
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
    }
    
    // MARK: - Playhead View
    
    @ViewBuilder
    private func playheadView() -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .shadow(color: .black.opacity(0.5), radius: 2)
            
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 2, height: 20)
        }
    }
    
    // MARK: - Helper Methods
    
    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clamped = max(0, min(time, duration))
        return CGFloat(clamped / duration) * max(1, width - 24) + 12
    }
    
    private func nearestShot(atX x: CGFloat, totalWidth: CGFloat) -> MockShot? {
        guard !shots.isEmpty else { return nil }
        let pairs = shots.map { shot -> (MockShot, CGFloat) in
            let pos = xPosition(for: shot.time, width: totalWidth)
            return (shot, abs(pos - x))
        }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }
    
    private func select(_ shot: MockShot) {
        selectedShotID = shot.id
        currentTime = shot.time
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
}

// MARK: - Preview

#Preview("Enhanced Timeline") {
    struct PreviewWrapper: View {
        @State private var shots = Array<MockShot>.sampleShots(duration: 90)
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
