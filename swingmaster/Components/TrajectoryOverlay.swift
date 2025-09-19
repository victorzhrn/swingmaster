//
//  TrajectoryOverlay.swift
//  swingmaster
//
//  Pure Canvas renderer for precomputed trajectories.
//

import SwiftUI

struct TrajectoryOverlay: View {
    let trajectoriesByType: [TrajectoryType: [TrajectoryPoint]]
    let enabledTrajectories: Set<TrajectoryType>
    let currentTime: Double        // Relative to shot start
    let shotDuration: Double
    let videoAspectRatio: CGFloat

    @State private var showFullPath = false

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let videoRect = calculateVideoRect(viewSize: size, videoAspectRatio: videoAspectRatio)
                let progress = min(1.0, max(0, currentTime / max(shotDuration, 0.0001)))
                let hasStarted = currentTime > 0.01
                let hasCompleted = progress >= 0.95 || showFullPath

                for type in enabledTrajectories {
                    if let points = trajectoriesByType[type], !points.isEmpty {
                        drawTrajectory(context: context, points: points, color: color(for: type), videoRect: videoRect, progress: progress, showDotOnly: !hasStarted, showFullPath: hasCompleted)
                    }
                }
            }
        }
        .onChange(of: currentTime) { _, newTime in
            if shotDuration > 0, newTime / shotDuration >= 0.95 {
                withAnimation(.easeInOut(duration: 0.3)) { showFullPath = true }
            } else if newTime < 0.1 { showFullPath = false }
        }
    }

    private func color(for type: TrajectoryType) -> Color {
        switch type {
        case .rightWrist, .leftWrist: return TennisColors.aceGreen
        case .rightElbow, .leftElbow: return Color(hex: "#4169E1")
        case .rightShoulder, .leftShoulder: return Color(hex: "#FF6B6B")
        case .racketCenter: return TennisColors.tennisYellow
        case .ballCenter: return Color(hex: "#FFD700")
        }
    }

    private func calculateVideoRect(viewSize: CGSize, videoAspectRatio: CGFloat) -> CGRect {
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

    private func drawTrajectory(context: GraphicsContext,
                                points: [TrajectoryPoint],
                                color: Color,
                                videoRect: CGRect,
                                progress: Double,
                                showDotOnly: Bool,
                                showFullPath: Bool) {
        let screenPoints: [CGPoint] = points.map { p in
            CGPoint(x: videoRect.minX + CGFloat(p.x) * videoRect.width,
                    y: videoRect.minY + CGFloat(1.0 - p.y) * videoRect.height)
        }
        if showDotOnly {
            if let start = screenPoints.first {
                context.fill(Circle().path(in: CGRect(x: start.x - 12, y: start.y - 12, width: 24, height: 24)), with: .color(color.opacity(0.2)))
                context.fill(Circle().path(in: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(color))
            }
            return
        }
        let visibleCount = showFullPath ? screenPoints.count : max(1, Int(Double(screenPoints.count) * progress))
        let dataPairs = zip(screenPoints.prefix(visibleCount), points.prefix(visibleCount)).map { ($0, $1) }
        for i in 1..<dataPairs.count {
            let prev = dataPairs[i-1]
            let curr = dataPairs[i]
            var path = Path()
            path.move(to: prev.0)
            path.addLine(to: curr.0)
            let style = curr.1.isInterpolated ? StrokeStyle(lineWidth: 2, dash: [4, 2]) : StrokeStyle(lineWidth: 3)
            context.stroke(path, with: .color(color.opacity(curr.1.isInterpolated ? 0.5 : 0.8)), style: style)
        }
        if let last = dataPairs.last {
            context.fill(Circle().path(in: CGRect(x: last.0.x - 5, y: last.0.y - 5, width: 10, height: 10)), with: .color(color))
        }
    }
}


