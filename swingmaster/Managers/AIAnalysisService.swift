//
//  AIAnalysisService.swift
//  swingmaster
//
//  Service for on-demand AI analysis of individual shots
//

import Foundation
import SwiftUI
import Vision
import os

@MainActor
class AIAnalysisService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var currentAnalysisID: UUID?
    
    private let geminiValidator: GeminiValidator
    private let metricsCalculator = MetricsCalculator()
    private let logger = Logger(subsystem: "com.swingmaster", category: "AIAnalysisService")
    
    init() {
        // Using the same API key as in ProcessingManager
        self.geminiValidator = GeminiValidator(apiKey: "AIzaSyDWvavah1RCf7acKBESKtp_vdVNf7cii8w")
    }
    
    func analyzeShot(_ shot: Shot, videoFileName: String, validatedSwing: ValidatedSwing? = nil, segmentMetrics: SegmentMetrics? = nil) async -> (strengths: [String], improvements: [String], score: Float)? {
        guard !shot.hasAIAnalysis else {
            // Already analyzed, return existing
            return (shot.strengths, shot.improvements, shot.score)
        }
        
        isAnalyzing = true
        currentAnalysisID = shot.id
        defer {
            isAnalyzing = false
            currentAnalysisID = nil
        }
        
        // Check if we have stored swing data or it was passed in
        guard let swing = validatedSwing ?? shot.validatedSwing else {
            logger.warning("No swing data available for shot \(shot.id)")
            return nil
        }
        
        // Use provided metrics or stored metrics or calculate
        let metrics = segmentMetrics ?? shot.segmentMetrics ?? metricsCalculator.calculateSegmentMetrics(for: swing.frames)
        
        // Call Gemini for real analysis
        do {
            logger.log("Starting AI analysis for shot \(shot.id) of type \(shot.type.rawValue)")
            let result = try await geminiValidator.analyzeSwing(swing, metrics: metrics)
            
            logger.log("AI analysis completed: score=\(result.score), strengths=\(result.strengths.count), improvements=\(result.improvements.count)")
            
            // Update storage
            AnalysisStore.updateShotAnalysis(
                videoFileName: videoFileName,
                shotID: shot.id,
                strengths: result.strengths,
                improvements: result.improvements,
                score: result.score
            )
            
            return (result.strengths, result.improvements, result.score)
        } catch {
            logger.error("AI analysis failed: \(error)")
            return nil
        }
    }
}