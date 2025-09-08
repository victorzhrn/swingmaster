//
//  SkeletonOverlay.swift
//  swingmaster
//
//  Draws a simple body skeleton using Vision joint names with confidence-based
//  coloring. Consumes PoseFrame (normalized coordinates) and converts to the
//  overlay view's coordinate space.
//

import SwiftUI
import Vision

/// Lightweight overlay for visualizing pose joints and bones.
struct SkeletonOverlay: View {
    let pose: PoseFrame?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let pose = pose else { return }

                // Draw bones
                for (a, b) in Self.bonePairs {
                    guard let pa = pose.joints[a], let pb = pose.joints[b] else { continue }
                    let ca = pose.confidences[a] ?? 0
                    let cb = pose.confidences[b] ?? 0
                    let color = Self.color(for: min(ca, cb))
                    let p1 = Self.convert(point: pa, in: size)
                    let p2 = Self.convert(point: pb, in: size)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    context.stroke(path, with: .color(color), lineWidth: 3)
                }

                // Draw joints
                for (name, p) in pose.joints {
                    let conf = pose.confidences[name] ?? 0
                    let color = Self.color(for: conf)
                    let pt = Self.convert(point: p, in: size)
                    let dot = Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6))
                    context.fill(dot, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    /// Convert from Vision's normalized (origin bottom-left) to SwiftUI's (origin top-left)
    private static func convert(point: CGPoint, in size: CGSize) -> CGPoint {
        let x = point.x * size.width
        let y = (1.0 - point.y) * size.height
        return CGPoint(x: x, y: y)
    }

    private static func color(for confidence: Float) -> Color {
        if confidence > 0.8 { return .green }
        if confidence > 0.5 { return .yellow }
        return .red
    }

    /// Minimal bone set covering arms, torso, legs.
    private static let bonePairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // Torso
        (.neck, .root),
        // Arms
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        // Shoulders to neck
        (.leftShoulder, .neck), (.rightShoulder, .neck),
        // Legs
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        // Hips to root
        (.leftHip, .root), (.rightHip, .root)
    ]
}


