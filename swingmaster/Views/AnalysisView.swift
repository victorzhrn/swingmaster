//
//  AnalysisView.swift
//  swingmaster
//
//  Accessible analysis screen with video placeholder, timeline strip, chips row,
//  and an insight card that updates with the selected shot.
//

import SwiftUI
import AVFoundation

struct AnalysisView: View {
    let videoURL: URL?
    let duration: Double
    let shots: [MockShot]

    @State private var selectedShotID: MockShot.ID?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var playingSegment: MockShot? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
        VStack(spacing: 12) {
            // Real video when available, otherwise placeholder
            Group {
                if let url = videoURL {
                    VideoPlayerView(
                        url: url,
                        currentTime: $currentTime,
                        isPlaying: $isPlaying,
                        segmentStart: playingSegment?.startTime,
                        segmentEnd: playingSegment?.endTime,
                        onSegmentComplete: {
                            // Segment playback completed
                            playingSegment = nil
                        }
                    )
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomLeading) {
                        persistentVideoControls
                            .padding(.leading, 12)
                            .padding(.bottom, 12)
                    }
                    .overlay(alignment: .bottom) {
                        shotNavigator
                            .padding(.bottom, 8)
                    }
                    .accessibilityLabel("Video player")
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        VStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.9))
                            Text(timeString(currentTime) + " / " + timeString(duration))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .frame(height: 320)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Video player")
                    .accessibilityValue("Time \(timeString(currentTime)) of \(timeString(duration))")
                }
            }

            // Enhanced Timeline Strip with segment expansion
            TimelineStripEnhanced(
                duration: duration,
                shots: shots,
                selectedShotID: $selectedShotID,
                currentTime: $currentTime,
                isPlaying: $isPlaying,
                onPlaySegment: { shot in
                    playSegment(shot)
                }
            )
            .padding(.horizontal, 16)

            // Removed ShotChipsRow in favor of minimal navigator overlay on video

            // Insight Card
            enhancedInsightCard
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .onAppear {
            if selectedShotID == nil, let first = shots.first { selectedShotID = first.id; currentTime = first.time }
        }
        .onChange(of: selectedShotID) { _, newID in
            // Auto-play the selected swing segment
            if let id = newID, let shot = shots.first(where: { $0.id == id }) {
                playSegment(shot)
            }
        }
        .onChange(of: currentTime) { _, t in
            // Update selection based on current playback position
            guard isPlaying, !shots.isEmpty, playingSegment == nil else { return }
            
            // Find which shot contains current time
            if let containingShot = shots.first(where: { t >= $0.startTime && t <= $0.endTime }) {
                if selectedShotID != containingShot.id {
                    selectedShotID = containingShot.id
                }
            }
        }
        
    }

    // MARK: - Subviews
    
    private var persistentVideoControls: some View {
        HStack(spacing: 16) {
            // Play/Pause (always visible)
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.9))
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.3))
                            .blur(radius: 10)
                    )
            }
            
            // Current segment info (if playing)
            if let segment = playingSegment {
                Text(segment.type.shortLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(segment.type.accentColor.opacity(0.8))
                    )
                    .foregroundColor(.white)
            }
        }
        .padding(12)
    }

    private var currentShotIndex: Int {
        if let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) {
            return idx
        }
        return 0
    }

    private var shotNavigator: some View {
        HStack {
            Button(action: selectPrev) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            Spacer()
            
            Text("Shot \(currentShotIndex + 1) of \(shots.count)")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.25))
                .clipShape(Capsule())
            
            Spacer()
            
            Button(action: selectNext) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
    }

    

    private var enhancedInsightCard: some View {
        let selected = shots.first(where: { $0.id == selectedShotID })
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selected?.type.accessibleName ?? "Shot")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text(String(format: "%.1f", selected?.score ?? 0))
                    .modifier(TennisTypography.MetricStyle())
                    .foregroundColor(scoreColor(selected?.score ?? 0))
            }
            .padding(.bottom, 4)
            
            // Strengths
            if let strengths = selected?.strengths, !strengths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What you did well", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TennisColors.aceGreen)
                    ForEach(strengths, id: \.self) { s in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(TennisColors.aceGreen)
                                .frame(width: 4, height: 4)
                                .offset(y: 6)
                            Text(s)
                                .font(.system(size: 15))
                                .foregroundColor(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            
            Divider().background((colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)))
            
            // Improvements
            if let improvements = selected?.improvements, !improvements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Focus on improving", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TennisColors.tennisYellow)
                    ForEach(Array(improvements.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(index == 0 ? TennisColors.tennisYellow : TennisColors.tennisYellow.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .offset(y: 6)
                            Text(text)
                                .font(.system(size: 15, weight: index == 0 ? .medium : .regular))
                                .foregroundColor(Color.primary.opacity(index == 0 ? 1 : 0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func scoreColor(_ score: Float) -> Color {
        if score >= 7.5 { return TennisColors.aceGreen }
        if score >= 5.5 { return TennisColors.tennisYellow }
        return TennisColors.clayOrange
    }

    // MARK: - Actions
    
    private func togglePlayback() {
        isPlaying.toggle()
        if !isPlaying { playingSegment = nil }
    }

    private func playSegment(_ shot: MockShot) {
        playingSegment = shot
        currentTime = shot.startTime
        isPlaying = true
    }
    
    private func replaySegment() {
        if let segment = playingSegment {
            currentTime = segment.startTime
            isPlaying = true
        } else if let id = selectedShotID, let shot = shots.first(where: { $0.id == id }) {
            playSegment(shot)
        }
    }

    private func selectPrev() {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = max(idx - 1, 0)
        let shot = shots[newIndex]
        selectedShotID = shot.id
        playSegment(shot)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func selectNext() {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = min(idx + 1, shots.count - 1)
        let shot = shots[newIndex]
        selectedShotID = shot.id
        playSegment(shot)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func timeString(_ t: Double) -> String {
        let seconds = Int(t.rounded())
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func currentSelectedIndexOrNearest(to time: Double) -> Int? {
        if let sel = selectedShotID, let idx = shots.firstIndex(where: { $0.id == sel }) { return idx }
        // Fallback: nearest by absolute time
        let pairs = shots.enumerated().map { ($0.offset, abs($0.element.time - time)) }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }
}

#Preview("AnalysisView") {
    let shots = Array<MockShot>.sampleShots(duration: 92)
    return AnalysisView(videoURL: nil, duration: 92, shots: shots)
}


