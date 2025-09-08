//
//  VideoPlayerView.swift
//  swingmaster
//
//  Simple AVPlayer wrapper with play/pause and time observation.
//

import SwiftUI
import AVFoundation
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Always ensure the player points at the latest URL
        if let currentAsset = (uiViewController.player?.currentItem?.asset as? AVURLAsset), currentAsset.url == url {
            return
        }
        uiViewController.player = AVPlayer(url: url)
    }
}


