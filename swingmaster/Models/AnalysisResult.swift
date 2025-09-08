//
//  AnalysisResult.swift
//  swingmaster
//
//  Finalized analysis for a swing segment. In MVP this is a lightweight
//  container to be expanded by MetricsCalculator and GeminiValidator.
//

import Foundation

public struct AnalysisResult: Sendable, Identifiable {
    public var id: UUID
    public var segment: SwingSegment
    public var primaryInsight: String
    public var score: Float

    public init(id: UUID = UUID(), segment: SwingSegment, primaryInsight: String, score: Float) {
        self.id = id
        self.segment = segment
        self.primaryInsight = primaryInsight
        self.score = score
    }
}


