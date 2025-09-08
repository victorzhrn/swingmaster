//
//  SessionStore.swift
//  swingmaster
//
//  Lightweight session persistence using UserDefaults for MVP.
//

import Foundation

struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let videoPath: String
    let shotCount: Int

    var videoURL: URL { URL(fileURLWithPath: videoPath) }
}

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let storageKey = "SessionStore.sessions"

    init() {
        load()
    }

    func save(videoURL: URL, shotCount: Int) {
        let session = Session(id: UUID(), date: Date(), videoPath: videoURL.path, shotCount: shotCount)
        sessions.insert(session, at: 0)
        persist()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Session].self, from: data) {
            sessions = decoded
        }
    }
}


