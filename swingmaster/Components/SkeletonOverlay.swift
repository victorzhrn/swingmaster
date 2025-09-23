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
    /// Optional video aspect ratio (width/height). When provided, the overlay
    /// aligns skeleton drawing to the letterboxed video rect instead of filling
    /// the entire view bounds.
    var videoAspectRatio: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let pose = pose else { return }
                let videoRect: CGRect
                if let ar = videoAspectRatio {
                    videoRect = Self.calculateVideoRect(viewSize: size, videoAspectRatio: ar)
                } else {
                    videoRect = CGRect(origin: .zero, size: size)
                }

                // Draw bones
                for (a, b) in Self.bonePairs {
                    guard let pa = pose.joints[a], let pb = pose.joints[b] else { continue }
                    let ca = pose.confidences[a] ?? 0
                    let cb = pose.confidences[b] ?? 0
                    let minConf = min(ca, cb)
                    // Skip very low confidence connections entirely
                    if minConf < Self.minimumConfidenceToDraw { continue }
                    let color = Self.color(for: minConf).opacity(Self.opacity(for: minConf))
                    let p1 = Self.map(point: pa, into: videoRect)
                    let p2 = Self.map(point: pb, into: videoRect)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    context.stroke(path, with: .color(color), lineWidth: 4)
                }

                // Draw joints (excluding facial features for cleaner visualization)
                for (name, p) in pose.joints {
                    // Skip facial joints entirely - focus on body mechanics
                    if [.nose, .leftEye, .rightEye, .leftEar, .rightEar].contains(name) {
                        continue
                    }
                    
                    let conf = pose.confidences[name] ?? 0
                    if conf < Self.minimumConfidenceToDraw { continue }
                    let color = Self.color(for: conf).opacity(Self.opacity(for: conf))
                    let pt = Self.map(point: p, into: videoRect)
                    let dot = Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    /// Map Vision normalized point (origin bottom-left) into the specified rect
    /// within the view's coordinate space (origin top-left).
    private static func map(point: CGPoint, into rect: CGRect) -> CGPoint {
        let x = rect.minX + point.x * rect.width
        let y = rect.minY + (1.0 - point.y) * rect.height
        return CGPoint(x: x, y: y)
    }

    /// Calculate the letterboxed video rect for a given aspect ratio.
    private static func calculateVideoRect(viewSize: CGSize, videoAspectRatio: CGFloat) -> CGRect {
        let viewAspect = viewSize.width / viewSize.height
        var videoWidth: CGFloat
        var videoHeight: CGFloat
        if videoAspectRatio > viewAspect {
            videoWidth = viewSize.width
            videoHeight = viewSize.width / videoAspectRatio
        } else {
            videoHeight = viewSize.height
            videoWidth = viewSize.height * videoAspectRatio
        }
        let x = (viewSize.width - videoWidth) / 2
        let y = (viewSize.height - videoHeight) / 2
        return CGRect(x: x, y: y, width: videoWidth, height: videoHeight)
    }

    private static let minimumConfidenceToDraw: Float = 0.25

    /// Confidence-to-opacity mapping favoring transparency at low confidence
    private static func opacity(for confidence: Float) -> Double {
        // Map [0,1] -> [0.2, 1.0] with slight gamma to fade low confidence
        let clamped = max(0, min(1, Double(confidence)))
        let gamma = pow(clamped, 1.5)
        return 0.2 + 0.8 * gamma
    }

    private static func color(for confidence: Float) -> Color {
        if confidence > 0.8 { return TennisColors.aceGreen }
        if confidence > 0.5 { return TennisColors.tennisGreen }
        return TennisColors.tennisYellow
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


