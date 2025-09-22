//
//  ProcessingManager.swift
//  swingmaster
//
//  Handles multiple concurrent video processing tasks
//

import Foundation
import Combine
import os

@MainActor
final class ProcessingManager: ObservableObject {
    static let shared = ProcessingManager()
    
    @Published private(set) var activeProcessors: [UUID: VideoProcessor] = [:]
    
    private let processingQueue = DispatchQueue(
        label: "com.swingmaster.processing",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let maxConcurrentProcessing = 2
    private var currentProcessingCount = 0
    private var pendingQueue: [(Session, URL)] = []
    
    private var cancellables = Set<AnyCancellable>()
    @Published var scrollToSession: UUID?
    private let logger = Logger(subsystem: "com.swingmaster", category: "ProcessingManager")
    
    private init() {}
    
    // MARK: - Public API
    
    func startProcessing(for session: Session, videoURL: URL, sessionStore: SessionStore) {
        if currentProcessingCount >= maxConcurrentProcessing {
            pendingQueue.append((session, videoURL))
            sessionStore.updateSession(session.id) { 
                $0.processingStatus = .pending 
            }
            return
        }
        
        Task {
            await processVideo(session: session, videoURL: videoURL, sessionStore: sessionStore)
        }
    }
    
    func cancelProcessing(for sessionID: UUID) {
        activeProcessors[sessionID] = nil
    }
    
    func retryProcessing(for session: Session, sessionStore: SessionStore) {
        guard session.retryCount < session.maxRetries else { return }
        
        sessionStore.updateSession(session.id) { 
            $0.retryCount += 1
            $0.processingStatus = .pending
        }
        
        startProcessing(for: session, videoURL: session.videoURL, sessionStore: sessionStore)
    }
    
    // MARK: - Private Processing
    
    private func processVideo(session: Session, videoURL: URL, sessionStore: SessionStore) async {
        currentProcessingCount += 1
        defer { 
            currentProcessingCount -= 1
            processNextInQueue(sessionStore: sessionStore)
        }
        
        let processor = VideoProcessor(geminiAPIKey: "AIzaSyDWvavah1RCf7acKBESKtp_vdVNf7cii8w")
        activeProcessors[session.id] = processor
        
        processor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak sessionStore] state in
                sessionStore?.updateSession(session.id) { session in
                    session.processingStatus = self.mapProcessorState(state)
                }
            }
            .store(in: &cancellables)
        
        let results = await processor.processVideo(videoURL)
        
        await MainActor.run {
            sessionStore.updateSession(session.id) { session in
                session.processingStatus = .complete
                session.lastError = nil
            }
            activeProcessors[session.id] = nil
            
            // Save results using AnalysisStore
            let duration = VideoStorage.getDurationSeconds(for: session.videoURL)
            let shots = results.map { res in
                let t = (res.segment.startTime + res.segment.endTime) / 2.0
                
                // Extract padded frames from the result
                let paddedPoseFrames = res.segment.frames  // These are already padded from VideoProcessor
                let paddedObjectFrames = res.objectFrames
                
                let shot = Shot(
                    id: res.id,
                    time: t,
                    type: res.swingType,
                    startTime: res.segment.startTime,
                    endTime: res.segment.endTime,
                    segmentMetrics: res.segmentMetrics,  // Simple metrics for UI
                    paddedPoseFrames: paddedPoseFrames,  // Store padded pose frames
                    paddedObjectFrames: paddedObjectFrames  // Store padded object frames
                )
                self.logger.log("[Save] Shot type=\(shot.type.rawValue, privacy: .public) startTS=\(shot.startTime, privacy: .public) endTS=\(shot.endTime, privacy: .public) duration=\(shot.duration, format: .fixed(precision: 3)) poses=\(paddedPoseFrames.count) objects=\(paddedObjectFrames.count)")
                return shot
            }
            AnalysisStore.save(videoURL: session.videoURL, duration: duration, shots: shots)
            sessionStore.updateSession(session.id) { session in
                session.shotCount = shots.count
            }
        }
    }
    
    
    private func processNextInQueue(sessionStore: SessionStore) {
        guard !pendingQueue.isEmpty,
              currentProcessingCount < maxConcurrentProcessing else { return }
        
        let (session, url) = pendingQueue.removeFirst()
        Task {
            await processVideo(session: session, videoURL: url, sessionStore: sessionStore)
        }
    }
    
    private func mapProcessorState(_ state: VideoProcessor.ProcessingState) -> Session.ProcessingStatus {
        switch state {
        case .extractingPoses(let progress):
            return .extractingPoses(progress: progress)
        case .calculatingMetrics:
            return .calculatingMetrics
        case .detectingSwings:
            return .detectingSwings
        case .validatingSwings(let current, let total):
            return .validatingSwings(current: current, total: total)
        case .complete:
            return .complete
        }
    }
}