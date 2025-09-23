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
    // Pro comparison state
    @State private var proShot: Shot? = nil
    @State private var proTrajectories: [TrajectoryType: [TrajectoryPoint]] = [:]
    @State private var proVideoAspectRatio: CGFloat = 16.0/9.0
    @State private var proCurrentTime: Double = 0
    @State private var proIsPlaying: Bool = false
    @State private var proSegmentStart: Double? = nil
    @State private var proSegmentEnd: Double? = nil

    // MARK: - Keyframe tabs
    @State private var selectedKeyframeIndex: Int = 0

    // MARK: - Skeleton state
    @State private var showSkeleton: Bool = false
    @State private var skeletonOnly: Bool = false
    @State private var currentUserPose: PoseFrame? = nil
    @State private var currentProPose: PoseFrame? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base Layer: Full-screen video (kept for playback; visually hidden in Skeleton Only)
                videoLayer(geometry: geometry)
                    .opacity(skeletonOnly ? 0 : 1)
                
                // Overlay Layer 1: Skeleton or Trajectory visualization
                if let shot = shots.first(where: { $0.id == selectedShotID }) {
                    if showSkeleton {
                        if isComparing {
                            HStack(spacing: 1) {
                                SkeletonOverlay(pose: currentUserPose, videoAspectRatio: videoAspectRatio)
                                    .frame(width: geometry.size.width / 2)
                                    .allowsHitTesting(false)
                                SkeletonOverlay(pose: currentProPose, videoAspectRatio: proVideoAspectRatio)
                                    .frame(width: geometry.size.width / 2)
                                    .allowsHitTesting(false)
                            }
                        } else {
                            SkeletonOverlay(pose: currentUserPose, videoAspectRatio: videoAspectRatio)
                                .allowsHitTesting(false)
                        }
                    } else {
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
                }
                
                // Overlay Layer 2: Metrics bar (top)
                VStack {
                    SwingMetricsBar(shot: shots.first(where: { $0.id == selectedShotID }))
                        .padding(.top, geometry.safeAreaInsets.top)
                    Spacer()
                }
                
                // Overlay Layer 3: Floating controls + Navigation panel
                VStack {
                    Spacer()

                    // Floating controls layer
                    HStack(alignment: .bottom) {
                        ViewModeControl(enabledTrajectories: $enabledTrajectories, showSkeleton: $showSkeleton, skeletonOnly: $skeletonOnly)

                        Spacer()
                        
                        CompareToggle(isComparing: $isComparing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    // Navigation panel (full width)
                    VStack(spacing: 8) {
                        KeyframeTabs(
                            shot: shots.first(where: { $0.id == selectedShotID }),
                            currentTime: $currentTime,
                            selectedIndex: $selectedKeyframeIndex
                        )

                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 0.5)

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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
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
        .onChange(of: currentTime) { _, _ in
            guard showSkeleton, let shot = shots.first(where: { $0.id == selectedShotID }) else { return }
            currentUserPose = nearestPose(in: shot.paddedPoseFrames, at: currentTime)
            if isComparing, let pro = proShot {
                let userOffset = max(0, currentTime - shot.startTime)
                let clampedOffset = min(userOffset, max(0, pro.endTime - pro.startTime))
                let proTime = pro.startTime + clampedOffset
                currentProPose = nearestPose(in: pro.paddedPoseFrames, at: proTime)
                // Keep pro player time loosely in sync with mapped time
                if abs(proCurrentTime - proTime) > 0.05 {
                    proCurrentTime = proTime
                }
            } else {
                currentProPose = nil
            }
        }
        // view mode changes are handled by ViewModeControl via bindings
        // Decouple pro playback so pro shot can finish even if user shot is shorter
        .onChange(of: enabledTrajectories) { _, _ in
            // Mirror left-side precompute: ensure pro trajectories update when selection changes
            if isComparing, let shot = proShot {
                var map = proTrajectories
                for t in enabledTrajectories where map[t] == nil {
                    map[t] = TrajectoryComputer.compute(
                        type: t,
                        poseFrames: shot.paddedPoseFrames,
                        objectFrames: shot.paddedObjectFrames,
                        startTime: shot.startTime,
                        options: trajectoryOptions
                    )
                }
                proTrajectories = map
            }
        }
        .onChange(of: isComparing) { _, newValue in
            if newValue {
                // Load pro shot analysis and precompute trajectories for enabled types
                proShot = ProVideoLoader.loadShot(named: "DjokvicForhand")
                if let proURL = Bundle.main.url(forResource: "DjokvicForhand", withExtension: "mov") {
                    loadProAspectRatio(from: proURL)
                }
                if let shot = proShot {
                    proSegmentStart = shot.startTime
                    proSegmentEnd = shot.endTime
                    var map: [TrajectoryType: [TrajectoryPoint]] = [:]
                    for t in enabledTrajectories {
                        map[t] = TrajectoryComputer.compute(
                            type: t,
                            poseFrames: shot.paddedPoseFrames,
                            objectFrames: shot.paddedObjectFrames,
                            startTime: shot.startTime,
                            options: trajectoryOptions
                        )
                    }
                    proTrajectories = map
                    // One-time alignment of pro playback time/state when compare starts
                    if let userShot = shots.first(where: { $0.id == selectedShotID }) {
                        let userOffset = max(0, currentTime - userShot.startTime)
                        proCurrentTime = shot.startTime + userOffset
                        proIsPlaying = isPlaying
                        if showSkeleton {
                            let clampedOffset = min(userOffset, max(0, shot.endTime - shot.startTime))
                            let proTime = shot.startTime + clampedOffset
                            currentProPose = nearestPose(in: shot.paddedPoseFrames, at: proTime)
                        }
                    }
                }
            } else {
                proShot = nil
                proTrajectories = [:]
                proIsPlaying = false
                currentProPose = nil
                proSegmentStart = nil
                proSegmentEnd = nil
            }
        }
        .onChange(of: showSkeleton) { _, enabled in
            if enabled {
                if let shot = shots.first(where: { $0.id == selectedShotID }) {
                    currentUserPose = nearestPose(in: shot.paddedPoseFrames, at: currentTime)
                }
                if isComparing, let pro = proShot, let user = shots.first(where: { $0.id == selectedShotID }) {
                    let userOffset = max(0, currentTime - user.startTime)
                    let clampedOffset = min(userOffset, max(0, pro.endTime - pro.startTime))
                    let proTime = pro.startTime + clampedOffset
                    currentProPose = nearestPose(in: pro.paddedPoseFrames, at: proTime)
                }
                trajectoryCache.removeAll()
            } else {
                currentUserPose = nil
                currentProPose = nil
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
                        currentTime: $proCurrentTime,
                        isPlaying: $proIsPlaying, // Independent play/pause
                        showsControls: false,
                        segmentStart: proSegmentStart,
                        segmentEnd: proSegmentEnd,
                        onSegmentComplete: {
                            proIsPlaying = false
                        }
                    )
                    .frame(width: geometry.size.width / 2)
                    .clipped() // Handle narrower aspect ratio
                    .overlay(proVideoLabel, alignment: .topLeading)
                    .overlay(alignment: .center) {
                        if !showSkeleton {
                            if let pro = proShot {
                                TrajectoryOverlay(
                                    trajectoriesByType: proTrajectories,
                                    enabledTrajectories: enabledTrajectories,
                                    // Show full pro trajectory in compare mode
                                    currentTime: max(0, pro.endTime - pro.startTime),
                                    shotDuration: max(0, pro.endTime - pro.startTime),
                                    videoAspectRatio: proVideoAspectRatio
                                )
                            }
                        }
                    }
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
        // Align and start pro playback if available; let pro play full shot even if user shot is shorter
        if isComparing, let pro = proShot {
            proCurrentTime = pro.startTime
            proIsPlaying = true
            proSegmentStart = pro.startTime
            proSegmentEnd = pro.endTime
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

    // Pro video aspect ratio
    fileprivate func loadProAspectRatio(from url: URL) {
        Task {
            let asset = AVAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let size = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            guard let size = size else { return }
            let transformed = size.applying(transform ?? .identity)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            await MainActor.run { self.proVideoAspectRatio = width / height }
        }
    }

    // Map user's current shot-relative time to pro video time
    fileprivate var proVideoTime: Double {
        guard let userShot = shots.first(where: { $0.id == selectedShotID }), let pro = proShot else { return 0 }
        let userOffset = max(0, currentTime - userShot.startTime)
        return pro.startTime + userOffset
    }

    fileprivate func nearestPose(in frames: [PoseFrame], at time: Double) -> PoseFrame? {
        if frames.isEmpty { return nil }
        // Binary search for closest frame at absolute time
        var lo = 0
        var hi = frames.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if frames[mid].timestamp < time {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo == 0 { return frames[0] }
        let a = frames[lo - 1]
        let b = frames[lo]
        return abs(a.timestamp - time) <= abs(b.timestamp - time) ? a : b
    }
}

// MARK: - Local Components (KeyframeTabs)

private struct KeyframeTabs: View {
    let shot: Shot?
    @Binding var currentTime: Double
    @Binding var selectedIndex: Int

    // Consistent naming: preparation, backswing, contact, follow through, recovery
    private let keyframeLabels = ["Preparation", "Backswing", "Contact", "Follow Through", "Recovery"]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<keyframeLabels.count, id: \.self) { index in
                Button(action: {
                    selectedIndex = index
                    if let s = shot {
                        let t = timeForKeyframe(index: index, shot: s)
                        currentTime = t
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    VStack(spacing: 2) {
                        Text(keyframeLabels[index])
                            .font(.subheadline)
                        Text(timeTextForKeyframe(index: index))
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    .foregroundColor(selectedIndex == index ? TennisColors.tennisGreen : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedIndex == index ? TennisColors.tennisGreen.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(height: 44)
    }

    private func timeForKeyframe(index: Int, shot: Shot) -> Double {
        if let times = shot.keyFrameTimes {
            // Map index to absolute time
            switch index {
            case 0: return clamp(times.preparation, shot: shot)
            case 1: return clamp(times.backswing, shot: shot)
            case 2: return clamp(times.contact, shot: shot)
            case 3: return clamp(times.followThrough, shot: shot)
            case 4: return clamp(times.recovery, shot: shot)
            default: break
            }
        }
        // Fallback: proportional fractions
        let fractions: [Double] = [0.0, 1.0/3.0, 0.5, 2.0/3.0, 1.0]
        let f = fractions[min(max(index, 0), fractions.count - 1)]
        return shot.startTime + f * shot.duration
    }

    private func timeTextForKeyframe(index: Int) -> String {
        guard let s = shot else { return "--" }
        let t = timeForKeyframe(index: index, shot: s) - s.startTime
        return String(format: "%.1fs", t)
    }

    private func clamp(_ t: Double, shot: Shot) -> Double {
        return min(max(t, shot.startTime), shot.endTime)
    }
}

// ViewModeControl binds directly to enabledTrajectories and showSkeleton

#Preview("AnalysisView") {
    let shots = Array<Shot>.sampleShots(duration: 92)
    return AnalysisView(videoURL: nil, duration: 92, shots: shots)
}


