//
//  SwingSegment.swift
//  swingmaster
//
//  A detected swing segment composed of a contiguous sequence of PoseFrames
//  with start/end timestamps. Classification and metrics are added later in
//  the pipeline.
//

import Foundation

public struct SwingSegment: Sendable, Identifiable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var frames: [PoseFrame]

    public init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, frames: [PoseFrame]) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.frames = frames
    }
}


