//
//  SessionStore.swift
//  swingmaster
//
//  Lightweight session persistence using UserDefaults for MVP.
//

import Foundation

extension Session {
    enum ProcessingStatus: Codable, Equatable, Hashable {
        case pending
        case extractingPoses(progress: Float)
        case calculatingMetrics
        case detectingSwings
        case validatingSwings(current: Int, total: Int)
        case analyzingSwings(current: Int, total: Int)
        case complete
        case failed(error: String)
        
        var isProcessing: Bool {
            switch self {
            case .complete, .failed:
                return false
            default:
                return true
            }
        }
        
        var canShowPartialResults: Bool {
            switch self {
            case .validatingSwings, .analyzingSwings, .complete:
                return true
            default:
                return false
            }
        }
        
        var statusText: String {
            switch self {
            case .pending: return "Preparing..."
            case .extractingPoses: return "Detecting motion"
            case .calculatingMetrics: return "Calculating metrics"
            case .detectingSwings: return "Finding swings"
            case .validatingSwings(let c, let t): return "Validating \(c)/\(t)"
            case .analyzingSwings(let c, let t): return "AI Analysis \(c)/\(t)"
            case .complete: return "Ready"
            case .failed(let error): return "Failed: \(error)"
            }
        }
    }
}

struct Session: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let date: Date
    let videoPath: String
    var shotCount: Int
    
    var processingStatus: ProcessingStatus = .pending
    var processorID: UUID?
    
    var lastError: String?
    var retryCount: Int = 0
    var maxRetries: Int = 3
    var thumbnailPath: String?

    /// Resolves the stored `videoPath` into a usable file URL.
    /// We store only the file name for stability across reinstalls.
    /// If an absolute path was stored previously, migrate by falling back to its lastPathComponent.
    var videoURL: URL {
        let fileManager = FileManager.default
        if videoPath.hasPrefix("/") {
            let absolute = URL(fileURLWithPath: videoPath)
            if fileManager.fileExists(atPath: absolute.path) {
                return absolute
            }
            // Fall back to Documents/<lastPathComponent>
            let fileName = absolute.lastPathComponent
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent(fileName)
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent(videoPath)
        }
    }
}

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let storageKey = "SessionStore.sessions"

    init() {
        load()
    }

    func save(videoURL: URL, shotCount: Int) {
        // Persist only the file name for stability across container changes
        let fileName = videoURL.lastPathComponent
        let session = Session(id: UUID(), date: Date(), videoPath: fileName, shotCount: shotCount)
        sessions.insert(session, at: 0)
        persist()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }
    
    func updateSession(_ id: UUID, update: (inout Session) -> Void) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            update(&sessions[index])
            persist()
        }
    }
    
    func add(_ session: Session) {
        sessions.insert(session, at: 0)
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
            // Migrate any entries that stored absolute paths to just file names
            let migrated: [Session] = decoded.map { s in
                let fileName = URL(fileURLWithPath: s.videoPath).lastPathComponent
                if fileName != s.videoPath {
                    return Session(id: s.id, date: s.date, videoPath: fileName, shotCount: s.shotCount)
                }
                return s
            }
            sessions = migrated
            if migrated != decoded {
                persist()
            }
        }
    }
}


