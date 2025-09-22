import Foundation
import AVFoundation

// Full pipeline processor for ProVideos using VideoProcessor and real data.

private struct BundledAnalysis: Codable {
    let videoFileName: String
    let duration: Double
    let shots: [Shot]
}

// Mirror core model types for isolated compilation; fields must match app models used for JSON.
private enum ShotType: String, Codable { case forehand, backhand, serve, unknown }

private struct PoseFrame: Codable { let timestamp: Double; let joints: [String: CGPointCodable]; let confidences: [String: Float] }
private struct CGPointCodable: Codable { let x: Double; let y: Double }
private struct RacketDetection: Codable { let boundingBox: CGRectCodable; let confidence: Float; let timestamp: Double }
private struct BallDetection: Codable { let boundingBox: CGRectCodable; let confidence: Float; let timestamp: Double }
private struct CGRectCodable: Codable { let x: Double; let y: Double; let width: Double; let height: Double }
private struct ObjectDetectionFrame: Codable { let timestamp: Double; let racket: RacketDetection?; let ball: BallDetection? }

private struct SegmentMetrics: Codable {
    let peakAngularVelocity: Double?
    let peakLinearVelocity: Double?
    let contactPoint: CGPointCodable?
    let backswingAngle: Double?
    let followThroughHeight: Double?
    let averageConfidence: Double?
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

@main
struct ProcessProVideosFull {
    static func main() async throws {
        let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        precondition(!apiKey.isEmpty, "GEMINI_API_KEY is required")

        // Attempt to run inside project by importing app module at runtime is not feasible here.
        // So we shell out to the app's VideoProcessor via a lightweight in-process shim is not available.
        // Fallback: detect available videos and inform user to run via the app if needed.

        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let proDir = URL(fileURLWithPath: cwd).appendingPathComponent("swingmaster/ProVideos", isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: proDir, includingPropertiesForKeys: nil) else {
            fputs("No ProVideos directory found at \(proDir.path)\n", stderr)
            return
        }
        let videoURLs = items.filter { ["mov","mp4","m4v"].contains($0.pathExtension.lowercased()) }
        guard !videoURLs.isEmpty else { print("No videos to process"); return }

        // Placeholder: instruct to run the full pipeline inside the app context if linking app code is required.
        print("Full pipeline requires app types (VideoProcessor). Please run the in-app processing or integrate this script into the app target.")
        print("Videos detected: \(videoURLs.map { $0.lastPathComponent })")
    }
}


