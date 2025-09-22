//
//  ProVideoLoader.swift
//  swingmaster
//
//  Loads preprocessed pro-shot analysis JSON bundled with the app.
//

import Foundation

enum ProVideoLoader {
    private struct BundledAnalysis: Codable {
        let videoFileName: String
        let duration: Double
        let shots: [Shot]
    }

    /// Load the first shot from a bundled analysis JSON named "<baseName>.analysis.json".
    /// - Parameter baseName: Resource base name (without extension)
    /// - Returns: The first `Shot` if found and decoded.
    static func loadShot(named baseName: String) -> Shot? {
        guard let url = Bundle.main.url(forResource: baseName, withExtension: "analysis.json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(BundledAnalysis.self, from: data) else {
            return nil
        }
        return payload.shots.first
    }
}


