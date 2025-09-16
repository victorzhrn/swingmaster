//
//  VideoStorage.swift
//  swingmaster
//
//  Handles persistence of recorded videos and thumbnail generation.
//

import Foundation
import AVFoundation
import UIKit

enum VideoStorage {
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Moves a temporary recorded file into the app Documents directory as a .mov.
    /// Returns the persisted URL.
    static func saveVideo(from tempURL: URL) -> URL {
        let fileName = UUID().uuidString + ".mov"
        let destination = documentsDirectory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            // Fallback: try copy if move fails
            _ = try? FileManager.default.copyItem(at: tempURL, to: destination)
        }
        return destination
    }

    /// Deletes a video file at the given URL if it exists.
    static func deleteVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Generates a thumbnail image for a video at the specified time (default 1s).
    static func generateThumbnail(for url: URL, at seconds: Double = 1.0) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    /// Returns the duration in seconds for the given video URL, or 0 when unavailable.
    static func getDurationSeconds(for url: URL) -> Double {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
    
    /// Async version of generateThumbnail
    static func generateThumbnail(for url: URL, at seconds: Double = 1.0) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if let image = generateThumbnail(for: url, at: seconds) {
                    let fileName = UUID().uuidString + ".jpg"
                    let path = documentsDirectory.appendingPathComponent(fileName)
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        try? data.write(to: path)
                        continuation.resume(returning: fileName)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}


