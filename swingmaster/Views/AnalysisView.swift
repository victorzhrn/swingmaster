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
    let shots: [Shot]

    @State private var selectedShotID: Shot.ID?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var playingSegment: Shot? = nil
    @Environment(\.colorScheme) private var colorScheme
    private let logger = Logger(subsystem: "com.swingmaster", category: "AnalysisView")

    // MARK: - Trajectories (computed from persisted data)
    @State private var enabledTrajectories: Set<TrajectoryType> = [.rightWrist]  // Start with wrist as default
    @State private var trajectoryOptions: TrajectoryOptions = .default
    @State private var videoAspectRatio: CGFloat = 16.0/9.0
    @State private var trajectoryCache: [UUID: [TrajectoryType: [TrajectoryPoint]]] = [:]
    @State private var isComparing: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base Layer: Full-screen video
                videoLayer(geometry: geometry)
                
                // Overlay Layer 1: Trajectory visualization
                if let shot = shots.first(where: { $0.id == selectedShotID }) {
                    if isComparing {
                        // Trajectory only on left (user) side
                        HStack(spacing: 1) { // Match the video spacing
                            TrajectoryOverlay(
                                trajectoriesByType: trajectoryCache[shot.id] ?? [:],
                                enabledTrajectories: enabledTrajectories,
                                currentTime: currentShotRelativeTime(shot: shot),
                                shotDuration: max(0, shot.endTime - shot.startTime),
                                videoAspectRatio: videoAspectRatio // Keep original aspect ratio
                            )
                            .frame(width: geometry.size.width / 2)
                            .clipped() // Match video clipping
                            .allowsHitTesting(false)
                            
                            Spacer()
                                .frame(width: geometry.size.width / 2)
                        }
                    } else {
                        // Original full-width trajectory
                        TrajectoryOverlay(
                            trajectoriesByType: trajectoryCache[shot.id] ?? [:],
                            enabledTrajectories: enabledTrajectories,
                            currentTime: currentShotRelativeTime(shot: shot),
                            shotDuration: max(0, shot.endTime - shot.startTime),
                            videoAspectRatio: videoAspectRatio
                        )
                        .allowsHitTesting(false)
                    }
                    
                    // Task handlers remain the same
                    TrajectoryOverlay(
                        trajectoriesByType: [:],
                        enabledTrajectories: [],
                        currentTime: 0,
                        shotDuration: 0,
                        videoAspectRatio: 1
                    )
                    .opacity(0)
                    .task(id: enabledTrajectories) { 
                        if let url = videoURL {
                            await precomputeIfNeeded(for: shot, videoURL: url) 
                        }
                    }
                    .task(id: selectedShotID) {
                        if let url = videoURL {
                            await precomputeIfNeeded(for: shot, videoURL: url)
                        }
                    }
                }
                
                // Overlay Layer 2: Metrics bar (top)
                VStack {
                    SwingMetricsBar(shot: shots.first(where: { $0.id == selectedShotID }))
                        .padding(.top, geometry.safeAreaInsets.top)
                    Spacer()
                }
                
                // Overlay Layer 3: Unified bottom control panel
                VStack {
                    Spacer()
                    
                    // Unified glass container for bottom controls
                    VStack(spacing: 0) {
                        // Trajectory selector row
                        TrajectorySelector(
                            enabledTrajectories: $enabledTrajectories,
                            isComparing: $isComparing
                        )
                        .padding(.horizontal, Spacing.small) // 8pt per design system
                        .padding(.vertical, Spacing.small)
                        
                        // Subtle divider
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                        
                        // Timeline strip row
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .background(.thinMaterial) // Medium glass effect
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1) // 15% white border
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16) // Consistent 16pt margins
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 8)
                }
            }
            .ignoresSafeArea(.container, edges: .all)
        }
        .onAppear {
            if selectedShotID == nil, let first = shots.first { selectedShotID = first.id; currentTime = first.time }
            if let url = videoURL { loadVideoAspectRatio(from: url) }
        }
        .onChange(of: selectedShotID) { _, newID in
            // Auto-play the selected swing segment
            if let id = newID, let shot = shots.first(where: { $0.id == id }) {
                playSegment(shot)
            }
        }
        
    }

    // MARK: - Subviews
    
    @ViewBuilder
    private func videoLayer(geometry: GeometryProxy) -> some View {
        if isComparing {
            // Split view with 1pt gap
            HStack(spacing: 1) {
                // User video (left) - narrower aspect
                Group {
                    if let url = videoURL {
                        VideoPlayerView(
                            url: url,
                            currentTime: $currentTime,
                            isPlaying: $isPlaying,
                            showsControls: false,
                            segmentStart: playingSegment?.startTime,
                            segmentEnd: playingSegment?.endTime,
                            onSegmentComplete: {
                                if let seg = playingSegment { 
                                    currentTime = seg.endTime 
                                }
                                isPlaying = false
                                playingSegment = nil
                            }
                        )
                    } else {
                        videoPlaceholder()
                    }
                }
                .frame(width: geometry.size.width / 2)
                .clipped() // Handle narrower aspect ratio
                .overlay(userVideoLabel, alignment: .topLeading)
                
                // Pro video (right) - local file
                if let proURL = Bundle.main.url(
                    forResource: "DjokvicForhand", 
                    withExtension: "mov"
                ) {
                    VideoPlayerView(
                        url: proURL,
                        currentTime: .constant(0),
                        isPlaying: $isPlaying, // Sync play/pause
                        showsControls: false
                    )
                    .frame(width: geometry.size.width / 2)
                    .clipped() // Handle narrower aspect ratio
                    .overlay(proVideoLabel, alignment: .topLeading)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .overlay(
                            VStack(spacing: Spacing.small) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 28)) // .large icon
                                    .foregroundColor(TennisColors.tennisYellow)
                                Text("Pro video not found")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        )
                        .frame(width: geometry.size.width / 2)
                }
            }
        } else {
            // Original full-screen video (existing code)
            Group {
                if let url = videoURL {
                    VideoPlayerView(
                        url: url,
                        currentTime: $currentTime,
                        isPlaying: $isPlaying,
                        showsControls: false,
                        segmentStart: playingSegment?.startTime,
                        segmentEnd: playingSegment?.endTime,
                        onSegmentComplete: {
                            if let seg = playingSegment { 
                                currentTime = seg.endTime 
                            }
                            isPlaying = false
                            playingSegment = nil
                        }
                    )
                    .accessibilityLabel("Video player")
                } else {
                    videoPlaceholder()
                }
            }
        }
    }
    
    // Label overlays using design system
    private var userVideoLabel: some View {
        Text("YOU")
            .font(.system(size: 11, weight: .bold)) // .caption2 bold
            .foregroundColor(.white)
            .padding(Spacing.micro) // 4pt
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(Spacing.small) // 8pt margin
    }
    
    private var proVideoLabel: some View {
        Text("PRO")
            .font(.system(size: 11, weight: .bold)) // .caption2 bold
            .foregroundColor(.white)
            .padding(Spacing.micro) // 4pt
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(Spacing.small) // 8pt margin
    }
    
    private func videoPlaceholder() -> some View {
        ZStack {
            Color.black
            VStack(spacing: Spacing.small) { // 8pt
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48)) // .xlarge icon
                    .foregroundColor(.white.opacity(0.3))
                Text(timeString(currentTime) + " / " + timeString(duration))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video player")
        .accessibilityValue("Time \(timeString(currentTime)) of \(timeString(duration))")
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
        if let url = videoURL {
            Task { await precomputeIfNeeded(for: shot, videoURL: url) }
        }
        isPlaying = true
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

// MARK: - Helpers in AnalysisView scope

extension AnalysisView {
    fileprivate func precomputeIfNeeded(for shot: Shot, videoURL: URL) async {
        // Use persisted data - no need to detect objects on-demand anymore!
        var perType: [TrajectoryType: [TrajectoryPoint]] = trajectoryCache[shot.id] ?? [:]
        
        for type in enabledTrajectories {
            if perType[type] == nil {
                // Use padded frames that are already persisted in Shot
                let poses = shot.paddedPoseFrames
                let objects = shot.paddedObjectFrames
                let points = TrajectoryComputer.compute(type: type, poseFrames: poses, objectFrames: objects, startTime: shot.startTime, options: trajectoryOptions)
                perType[type] = points
            }
        }
        trajectoryCache[shot.id] = perType
    }
    fileprivate func currentShotRelativeTime(shot: Shot) -> Double {
        max(0, currentTime - shot.startTime)
    }

    fileprivate func loadVideoAspectRatio(from url: URL) {
        Task {
            let asset = AVAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let size = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            guard let size = size else { return }
            let transformed = size.applying(transform ?? .identity)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            await MainActor.run { self.videoAspectRatio = width / height }
        }
    }
}

#Preview("AnalysisView") {
    let shots = Array<Shot>.sampleShots(duration: 92)
    return AnalysisView(videoURL: nil, duration: 92, shots: shots)
}


