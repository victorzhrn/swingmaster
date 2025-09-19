//
//  AnalysisView.swift
//  swingmaster
//
//  Accessible analysis screen with video placeholder, timeline strip, chips row,
//  and an insight card that updates with the selected shot.
//

import SwiftUI
import AVFoundation
import os

struct AnalysisView: View {
    let videoURL: URL?
    let duration: Double
    @State var shots: [Shot]  // Changed from let to @State for updates

    @StateObject private var aiService = AIAnalysisService()
    @State private var selectedShotID: Shot.ID?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var playingSegment: Shot? = nil
    @Environment(\.colorScheme) private var colorScheme
    private let logger = Logger(subsystem: "com.swingmaster", category: "AnalysisView")

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
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.glassBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: colorScheme == .light ? .black.opacity(0.1) : .clear, radius: 10, y: 5)
                    .overlay(alignment: .top) {
                        if let segment = playingSegment {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(segment.type.accessibleName)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                            .foregroundColor(.white)
                            .padding(.top, 8)
                        }
                    }
                    .accessibilityLabel("Video player")
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
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
                    .shadow(color: colorScheme == .light ? .black.opacity(0.1) : .clear, radius: 10, y: 5)
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
                },
                onPrev: selectPrev,
                onNext: selectNext
            )
            .padding(.horizontal, 16)

            // Navigation integrated into the timeline; no video overlays

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
        
        return GlassContainer(style: .medium, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(selected?.type.accessibleName ?? "Shot")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f", selected?.score ?? 0))
                        .modifier(TennisTypography.MetricStyle())
                        .foregroundColor(scoreColor(selected?.score ?? 0))
                }
                .padding(.bottom, 4)
                
                // AI Analysis Section
                if let selected = selected {
                    aiAnalysisSection(for: selected)
                }
            }
            .padding(16)
        }
    }

    private func scoreColor(_ score: Float) -> Color {
        if score >= 7.5 { return .shotExcellent }
        if score >= 5.5 { return .shotGood }
        return .shotNeedsWork
    }
    
    // NEW: AI Analysis Section
    @ViewBuilder
    private func aiAnalysisSection(for shot: Shot) -> some View {
        let isAnalyzing = aiService.isAnalyzing && aiService.currentAnalysisID == shot.id
        
        Group {
            if shot.hasAIAnalysis {
                // Show existing analysis
                VStack(alignment: .leading, spacing: 12) {
                    if !shot.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Strengths", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            
                            ForEach(shot.strengths, id: \.self) { strength in
                                HStack(alignment: .top) {
                                    Circle().fill(Color.green).frame(width: 4, height: 4).offset(y: 6)
                                    Text(strength).font(.body)
                                }
                            }
                        }
                    }
                    
                    if !shot.improvements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Areas to Improve", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            
                            ForEach(shot.improvements, id: \.self) { improvement in
                                HStack(alignment: .top) {
                                    Circle().fill(Color.orange).frame(width: 4, height: 4).offset(y: 6)
                                    Text(improvement).font(.body)
                                }
                            }
                        }
                    }
                }
                
            } else if isAnalyzing {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing your swing...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
            } else {
                // CTA Button
                Button(action: { Task { await generateAnalysis(for: shot) } }) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get AI Coaching")
                                .font(.headline)
                            Text("Personalized feedback for this shot")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(TennisColors.tennisYellow)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(TennisColors.tennisGreen.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(TennisColors.tennisGreen, lineWidth: 2)
                            )
                    )
                }
            }
        }
    }
    
    // NEW: Generate Analysis
    private func generateAnalysis(for shot: Shot) async {
        guard let videoFileName = videoURL?.lastPathComponent else { return }
        
        if let result = await aiService.analyzeShot(shot, 
                                                     videoFileName: videoFileName,
                                                     validatedSwing: shot.validatedSwing,
                                                     segmentMetrics: shot.segmentMetrics) {
            // Update the shot in our local state
            if let index = shots.firstIndex(where: { $0.id == shot.id }) {
                shots[index].strengths = result.strengths
                shots[index].improvements = result.improvements
                shots[index].score = result.score
                shots[index].hasAIAnalysis = true
            }
        }
    }

    // MARK: - Actions
    
    private func togglePlayback() {
        isPlaying.toggle()
        if !isPlaying { playingSegment = nil }
    }

    private func playSegment(_ shot: Shot) {
        logger.log("[UI] playSegment id=\(shot.id.uuidString, privacy: .public) start=\(shot.startTime, privacy: .public) end=\(shot.endTime, privacy: .public) duration=\(shot.duration, format: .fixed(precision: 3))")
        playingSegment = shot
        currentTime = shot.startTime
        isPlaying = true
    }
    
    private func replaySegment() {
        if let segment = playingSegment {
            logger.log("[UI] replaySegment start=\(segment.startTime, privacy: .public) end=\(segment.endTime, privacy: .public)")
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
    let shots = Array<Shot>.sampleShots(duration: 92)
    return AnalysisView(videoURL: nil, duration: 92, shots: shots)
}


