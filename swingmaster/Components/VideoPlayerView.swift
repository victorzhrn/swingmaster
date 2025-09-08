//
//  VideoPlayerView.swift
//  swingmaster
//
//  AVPlayer wrapper with bindings for currentTime and isPlaying, plus time observation and seeking.
//

import SwiftUI
import AVFoundation
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.showsPlaybackControls = true
        attachObserverIfNeeded(player: vc.player, coordinator: context.coordinator)
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        let coordinator = context.coordinator

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
            if player.rate == 0 { player.play() }
        } else {
            if player.rate != 0 { player.pause() }
        }

        // Seek if external currentTime deviates from player time
        let playerSeconds = coordinator.lastPlayerTimeSeconds
        if abs(currentTime - playerSeconds) > 0.2 {
            coordinator.isSeekingProgrammatically = true
            let target = CMTime(seconds: max(0, currentTime), preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                coordinator.isSeekingProgrammatically = false
            }
        }
    }

    private func attachObserverIfNeeded(player: AVPlayer?, coordinator: Coordinator) {
        guard let player = player, coordinator.timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        coordinator.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            coordinator.lastPlayerTimeSeconds = seconds
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
    }
}


