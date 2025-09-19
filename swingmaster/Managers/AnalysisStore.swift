//
//  AnalysisStore.swift
//  swingmaster
//
//  MVP persistence for per-video analysis results using UserDefaults.
//  Stores only the data required by AnalysisView: duration and Shot list.
//

import Foundation

/// Persisted analysis payload for a specific video file.
/// Keyed by the video file name (lastPathComponent) to be resilient to path changes.
struct PersistedAnalysis: Codable, Equatable {
    let videoFileName: String
    let duration: Double
    let shots: [Shot]
}

/// Lightweight store backed by UserDefaults for MVP.
/// Later this can be replaced or migrated to Core Data without changing AnalysisView.
enum AnalysisStore {
    private static let storageKey = "AnalysisStore.store"

    /// In-memory cache to minimize decode overhead.
    private static var cache: [String: PersistedAnalysis] = loadAll()

    /// Save analysis results for a given video URL.
    /// - Parameters:
    ///   - videoURL: The file URL for the analyzed video.
    ///   - duration: The total video duration in seconds.
    ///   - shots: The shots to display in AnalysisView.
    static func save(videoURL: URL, duration: Double, shots: [Shot]) {
        let fileName = videoURL.lastPathComponent
        var all = cache
        all[fileName] = PersistedAnalysis(videoFileName: fileName, duration: duration, shots: shots)
        persist(all)
        cache = all
    }

    /// Load persisted analysis for a given video URL, if available.
    /// - Parameter videoURL: The file URL for the analyzed video.
    /// - Returns: A persisted analysis payload, or nil if none exists.
    static func load(videoURL: URL) -> PersistedAnalysis? {
        let fileName = videoURL.lastPathComponent
        return cache[fileName]
    }


    /// Remove persisted analysis for a given video URL, if needed.
    static func delete(videoURL: URL) {
        let fileName = videoURL.lastPathComponent
        var all = cache
        all.removeValue(forKey: fileName)
        persist(all)
        cache = all
    }

    /// Clear all persisted analyses.
    static func clearAll() {
        persist([:])
        cache = [:]
    }
}

// MARK: - Private helpers

private extension AnalysisStore {
    static func loadAll() -> [String: PersistedAnalysis] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
        if let decoded = try? JSONDecoder().decode([String: PersistedAnalysis].self, from: data) {
            return decoded
        }
        return [:]
    }

    static func persist(_ dict: [String: PersistedAnalysis]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(dict) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
