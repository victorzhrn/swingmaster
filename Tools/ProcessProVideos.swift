import Foundation
import AVFoundation

// Minimal CLI tool to generate bundled analysis JSON for pro videos.
// This fallback does NOT run the full processing pipeline; it creates a single-shot
// payload per video using the entire clip duration and empty frame arrays so the
// app can load and render basic split-view comparison immediately.

private struct BundledAnalysis: Codable {
    let videoFileName: String
    let duration: Double
    let shots: [Shot]
}

// Mirror the app-side Shot and related types just enough for JSON compatibility.
private enum ShotType: String, Codable, CaseIterable {
    case forehand
    case backhand
    case serve
    case unknown
}

private struct Shot: Codable {
    let id: UUID
    let time: Double
    let startTime: Double
    let endTime: Double
    let type: ShotType
    let segmentMetrics: SegmentMetrics?
    let paddedPoseFrames: [PoseFrame]
    let paddedObjectFrames: [ObjectDetectionFrame]
}

private struct SegmentMetrics: Codable {
    let peakAngularVelocity: Double?
    let peakLinearVelocity: Double?
    let contactPoint: CGPointCodable?
    let backswingAngle: Double?
    let followThroughHeight: Double?
    let averageConfidence: Double?
}

private struct CGPointCodable: Codable {
    let x: Double
    let y: Double
}

private struct PoseFrame: Codable {}
private struct ObjectDetectionFrame: Codable {}

// MARK: - Script entry (top-level for `swift` interpreter)

let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let proDir = URL(fileURLWithPath: cwd).appendingPathComponent("swingmaster/ProVideos", isDirectory: true)

guard let items = try? fm.contentsOfDirectory(at: proDir, includingPropertiesForKeys: nil) else {
    fputs("No ProVideos directory found at \(proDir.path)\n", stderr)
    exit(1)
}

let videoURLs = items.filter { url in
    let ext = url.pathExtension.lowercased()
    return ["mov", "mp4", "m4v"].contains(ext)
}

if videoURLs.isEmpty {
    print("No video files found in \(proDir.path)")
    exit(0)
}

for url in videoURLs {
    do {
        let analysis = makeAnalysis(for: url)
        let outURL = url.deletingPathExtension().appendingPathExtension("analysis.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(analysis)
        try data.write(to: outURL, options: .atomic)
        print("Wrote: \(outURL.lastPathComponent) in \(proDir.path)")
    } catch {
        fputs("Failed to process \(url.lastPathComponent): \(error)\n", stderr)
    }
}

// MARK: - Helpers

private func makeAnalysis(for videoURL: URL) -> BundledAnalysis {
    let asset = AVURLAsset(url: videoURL)
    let durationSeconds = CMTimeGetSeconds(asset.duration)
    let start: Double = 0
    let end: Double = max(0, durationSeconds)
    let center: Double = (start + end) / 2.0

    let type = inferShotType(from: videoURL.lastPathComponent)
    let shot = Shot(
        id: UUID(),
        time: center,
        startTime: start,
        endTime: end,
        type: type,
        segmentMetrics: nil,
        paddedPoseFrames: [],
        paddedObjectFrames: []
    )
    return BundledAnalysis(videoFileName: videoURL.lastPathComponent, duration: durationSeconds, shots: [shot])
}

private func inferShotType(from fileName: String) -> ShotType {
    let s = fileName.lowercased()
    if s.contains("serve") || s.contains("srv") { return .serve }
    if s.contains("backhand") || s.contains("bh") { return .backhand }
    if s.contains("forehand") || s.contains("forhand") || s.contains("fh") { return .forehand }
    return .unknown
}


