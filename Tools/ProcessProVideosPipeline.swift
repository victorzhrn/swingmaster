import Foundation
import AVFoundation

// Full pipeline tool using app core types to generate real [Shot] JSON.

private struct BundledAnalysis: Codable {
    let videoFileName: String
    let duration: Double
    let shots: [Shot]
}

@main
struct ProcessProVideosPipeline {
    static func main() async {
        let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        if apiKey.isEmpty {
            fputs("GEMINI_API_KEY is required for full pipeline.\n", stderr)
            exit(1)
        }

        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let proDir = URL(fileURLWithPath: cwd).appendingPathComponent("swingmaster/ProVideos", isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: proDir, includingPropertiesForKeys: nil) else {
            fputs("No ProVideos directory found at \(proDir.path)\n", stderr)
            exit(1)
        }
        let videos = items.filter { ["mov","mp4","m4v"].contains($0.pathExtension.lowercased()) }
        if videos.isEmpty {
            print("No videos to process in \(proDir.path)")
            exit(0)
        }

        for url in videos {
            do {
                let analysis = try await processOne(url: url, apiKey: apiKey)
                let outURL = url.deletingPathExtension().appendingPathExtension("analysis.json")
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(analysis)
                try data.write(to: outURL, options: .atomic)
                print("Wrote: \(outURL.lastPathComponent)")
            } catch {
                fputs("Failed processing \(url.lastPathComponent): \(error)\n", stderr)
            }
        }
    }

    private static func processOne(url: URL, apiKey: String) async throws -> BundledAnalysis {
        let processor = await VideoProcessor(geminiAPIKey: apiKey)
        let results: [AnalysisResult] = await processor.processVideo(url)
        let duration = CMTimeGetSeconds(AVURLAsset(url: url).duration)

        let shots: [Shot] = results.map { res in
            let t = (res.segment.startTime + res.segment.endTime) / 2.0
            return Shot(
                id: res.id,
                time: t,
                type: res.swingType,
                startTime: res.segment.startTime,
                endTime: res.segment.endTime,
                segmentMetrics: res.segmentMetrics,
                paddedPoseFrames: res.segment.frames,
                paddedObjectFrames: res.objectFrames
            )
        }
        return BundledAnalysis(videoFileName: url.lastPathComponent, duration: duration, shots: shots)
    }
}
