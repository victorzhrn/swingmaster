//
//  VideoPlayerView.swift
//  swingmaster
//
//  AVPlayer wrapper with bindings for currentTime and isPlaying, plus time observation and seeking.
//

import SwiftUI
import AVFoundation
import AVKit
import os

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool
    var showsControls: Bool = false
    
    // Segment playback support
    var segmentStart: Double? = nil
    var segmentEnd: Double? = nil
    var onSegmentComplete: (() -> Void)? = nil
    private let logger = Logger(subsystem: "com.swingmaster", category: "VideoPlayer")

    func makeCoordinator() -> Coordinator { 
        Coordinator(segmentStart: segmentStart, segmentEnd: segmentEnd, onSegmentComplete: onSegmentComplete)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.showsPlaybackControls = showsControls
        attachObserverIfNeeded(player: vc.player, coordinator: context.coordinator)
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        let coordinator = context.coordinator
        uiViewController.showsPlaybackControls = showsControls

        // Swap player if URL changed
        if let currentAsset = (uiViewController.player?.currentItem?.asset as? AVURLAsset), currentAsset.url != url {
            if let player = uiViewController.player, let token = coordinator.timeObserver {
                player.removeTimeObserver(token)
                coordinator.timeObserver = nil
            }
            uiViewController.player?.pause()
            uiViewController.player = AVPlayer(url: url)
            attachObserverIfNeeded(player: uiViewController.player, coordinator: coordinator)
        } else if uiViewController.player == nil {
            uiViewController.player = AVPlayer(url: url)
            attachObserverIfNeeded(player: uiViewController.player, coordinator: coordinator)
        }

        guard let player = uiViewController.player else { return }

        // Sync play/pause state from binding
        if isPlaying {
            if player.rate == 0 {
                logger.log("[Player] Play requested (binding=true)")
                player.play()
            }
        } else {
            if player.rate != 0 {
                logger.log("[Player] Pause requested (binding=false)")
                player.pause()
            }
        }

        // Update segment boundaries if changed
        let previousStart = coordinator.segmentStart
        let previousEnd = coordinator.segmentEnd
        coordinator.segmentStart = segmentStart
        coordinator.segmentEnd = segmentEnd
        coordinator.onSegmentComplete = onSegmentComplete
        if previousEnd != segmentEnd || coordinator.lastLoggedBoundsEnd != segmentEnd || previousStart != segmentStart || coordinator.lastLoggedBoundsStart != segmentStart {
            coordinator.lastLoggedBoundsStart = segmentStart
            coordinator.lastLoggedBoundsEnd = segmentEnd
            logger.log("[Player] Segment bounds updated start=\(segmentStart ?? -1, privacy: .public) end=\(segmentEnd ?? -1, privacy: .public)")
            // Optionally jump to start when bounds change to ensure full segment playback
            if let s = segmentStart, abs((coordinator.lastPlayerTimeSeconds) - s) > 0.15 {
                coordinator.isSeekingProgrammatically = true
                coordinator.hasTriggeredSegmentEnd = false
                let target = CMTime(seconds: max(0, s), preferredTimescale: 600)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    coordinator.isSeekingProgrammatically = false
                    self.logger.log("[Player] Forced seek to segmentStart completed")
                }
            }
        }
        
        // Seek if external currentTime deviates from player time
        let playerSeconds = coordinator.lastPlayerTimeSeconds
        if abs(currentTime - playerSeconds) > 0.2 {
            logger.log("[Player] Seeking to t=\(currentTime, privacy: .public) from playerSeconds=\(playerSeconds, privacy: .public)")
            coordinator.isSeekingProgrammatically = true
            coordinator.hasTriggeredSegmentEnd = false  // Reset when seeking
            let target = CMTime(seconds: max(0, currentTime), preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                coordinator.isSeekingProgrammatically = false
                self.logger.log("[Player] Seek completed")
            }
        }
    }

    private func attachObserverIfNeeded(player: AVPlayer?, coordinator: Coordinator) {
        guard let player = player, coordinator.timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)  // Higher frequency for segment boundaries
        coordinator.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            coordinator.lastPlayerTimeSeconds = seconds
            
            // Check for segment boundary and auto-pause
            if let segEnd = coordinator.segmentEnd, 
               seconds >= segEnd - 0.1,  // Small buffer before end
               player.rate != 0,
               !coordinator.hasTriggeredSegmentEnd {
                coordinator.hasTriggeredSegmentEnd = true
                let segStart = coordinator.segmentStart ?? -1
                let played = segStart >= 0 ? max(0, seconds - segStart) : -1
                self.logger.log("[Player] Auto-pausing at seconds=\(seconds, privacy: .public) segStart=\(segStart, privacy: .public) segEnd=\(segEnd, privacy: .public) played=\(played, privacy: .public)")
                player.pause()
                isPlaying = false
                coordinator.onSegmentComplete?()
            }
            
            if !coordinator.isSeekingProgrammatically {
                if abs(seconds - currentTime) > 0.05 {
                    currentTime = seconds
                }
            }
            let playing = player.rate != 0
            if isPlaying != playing { isPlaying = playing }
        }
    }

    final class Coordinator {
        var timeObserver: Any?
        var lastPlayerTimeSeconds: Double = 0
        var isSeekingProgrammatically: Bool = false
        var segmentStart: Double?
        var segmentEnd: Double?
        var onSegmentComplete: (() -> Void)?
        var hasTriggeredSegmentEnd: Bool = false
        var lastLoggedBoundsStart: Double?
        var lastLoggedBoundsEnd: Double?
        
        init(segmentStart: Double? = nil, segmentEnd: Double? = nil, onSegmentComplete: (() -> Void)? = nil) {
            self.segmentStart = segmentStart
            self.segmentEnd = segmentEnd
            self.onSegmentComplete = onSegmentComplete
        }
    }
}


