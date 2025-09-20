//
//  TrajectoryOverlay.swift
//  swingmaster
//
//  Motion Quality Visualization with speed encoding, acceleration colors, and power spots.
//

import SwiftUI
import UIKit

struct TrajectoryOverlay: View {
    let trajectoriesByType: [TrajectoryType: [TrajectoryPoint]]
    let enabledTrajectories: Set<TrajectoryType>
    let currentTime: Double        // Relative to shot start
    let shotDuration: Double
    let videoAspectRatio: CGFloat

    @State private var showFullPath = false
    
    // Motion quality visualization settings
    private let minLineWidth: CGFloat = 2
    private let maxLineWidth: CGFloat = 6
    private let powerSpotRadius: CGFloat = 8
    private let powerSpotGlowRadius: CGFloat = 16

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let videoRect = calculateVideoRect(viewSize: size, videoAspectRatio: videoAspectRatio)
                let progress = min(1.0, max(0, currentTime / max(shotDuration, 0.0001)))
                let hasStarted = currentTime > 0.01
                let hasCompleted = progress >= 0.95 || showFullPath

                for type in enabledTrajectories {
                    if let points = trajectoriesByType[type], !points.isEmpty {
                        drawEnhancedTrajectory(
                            context: context,
                            points: points,
                            baseColor: color(for: type),
                            videoRect: videoRect,
                            progress: progress,
                            showDotOnly: !hasStarted,
                            showFullPath: hasCompleted
                        )
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

    private func drawEnhancedTrajectory(context: GraphicsContext,
                                       points: [TrajectoryPoint],
                                       baseColor: Color,
                                       videoRect: CGRect,
                                       progress: Double,
                                       showDotOnly: Bool,
                                       showFullPath: Bool) {
        // Convert to screen coordinates
        let screenPoints: [(point: CGPoint, data: TrajectoryPoint)] = points.map { p in
            let screenPoint = CGPoint(
                x: videoRect.minX + CGFloat(p.x) * videoRect.width,
                y: videoRect.minY + CGFloat(1.0 - p.y) * videoRect.height
            )
            return (screenPoint, p)
        }
        
        // Show starting position dot when not started
        if showDotOnly {
            if let start = screenPoints.first {
                // Outer glow
                context.fill(
                    Circle().path(in: CGRect(x: start.point.x - 12, y: start.point.y - 12, width: 24, height: 24)),
                    with: .color(baseColor.opacity(0.2))
                )
                // Inner dot
                context.fill(
                    Circle().path(in: CGRect(x: start.point.x - 4, y: start.point.y - 4, width: 8, height: 8)),
                    with: .color(baseColor)
                )
            }
            return
        }
        
        // Calculate visible points based on progress
        let visibleCount = showFullPath ? screenPoints.count : max(1, Int(Double(screenPoints.count) * progress))
        let visiblePoints = Array(screenPoints.prefix(visibleCount))
        
        // Calculate velocity range for normalization
        let velocities = visiblePoints.compactMap { $0.data.velocity }
        let maxVelocity = velocities.max() ?? 1.0
        let minVelocity = velocities.min() ?? 0.0
        let velocityRange = maxVelocity - minVelocity
        
        // Draw trajectory segments with variable width and color
        for i in 1..<visiblePoints.count {
            let prev = visiblePoints[i-1]
            let curr = visiblePoints[i]
            
            // Skip if no velocity data
            guard let velocity = curr.data.velocity else {
                // Fallback to simple line
                drawSimpleSegment(
                    context: context,
                    from: prev.point,
                    to: curr.point,
                    color: baseColor,
                    isInterpolated: curr.data.isInterpolated
                )
                continue
            }
            
            // Calculate line width based on velocity (2-6pt range)
            let normalizedVelocity = velocityRange > 0 ? 
                CGFloat((velocity - minVelocity) / velocityRange) : 0.5
            let lineWidth = minLineWidth + (maxLineWidth - minLineWidth) * normalizedVelocity
            
            // Calculate color based on acceleration (temperature shift)
            let segmentColor = calculateAccelerationColor(
                baseColor: baseColor,
                acceleration: curr.data.acceleration ?? 0
            )
            
            // Draw curved segment using bezier path
            drawCurvedSegment(
                context: context,
                from: prev.point,
                to: curr.point,
                prevPoint: i > 1 ? visiblePoints[i-2].point : nil,
                nextPoint: i < visiblePoints.count - 1 ? visiblePoints[i+1].point : nil,
                color: segmentColor,
                lineWidth: lineWidth,
                isInterpolated: curr.data.isInterpolated,
                opacity: calculateSegmentOpacity(index: i, total: visiblePoints.count, showFullPath: showFullPath)
            )
        }
        
        // Draw power spots (peak velocity points)
        for (i, pointData) in visiblePoints.enumerated() {
            if pointData.data.isPowerSpot {
                drawPowerSpot(
                    context: context,
                    at: pointData.point,
                    color: baseColor,
                    intensity: CGFloat(pointData.data.velocity ?? 1.0) / CGFloat(maxVelocity)
                )
            }
        }
        
        // Draw current position indicator
        if let last = visiblePoints.last, !showFullPath {
            drawCurrentPosition(context: context, at: last.point, color: baseColor)
        }
    }
    
    private func drawSimpleSegment(context: GraphicsContext,
                                  from: CGPoint,
                                  to: CGPoint,
                                  color: Color,
                                  isInterpolated: Bool) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        
        let style = isInterpolated ? 
            StrokeStyle(lineWidth: 2, dash: [4, 2]) : 
            StrokeStyle(lineWidth: 3)
        
        context.stroke(path, with: .color(color.opacity(isInterpolated ? 0.5 : 0.8)), style: style)
    }
    
    private func drawCurvedSegment(context: GraphicsContext,
                                  from: CGPoint,
                                  to: CGPoint,
                                  prevPoint: CGPoint?,
                                  nextPoint: CGPoint?,
                                  color: Color,
                                  lineWidth: CGFloat,
                                  isInterpolated: Bool,
                                  opacity: Double) {
        var path = Path()
        path.move(to: from)
        
        // Use bezier curve for smooth path
        if let prev = prevPoint, let next = nextPoint {
            // Calculate control points for smooth curve
            let controlPoint1 = CGPoint(
                x: from.x + (to.x - prev.x) * 0.15,
                y: from.y + (to.y - prev.y) * 0.15
            )
            let controlPoint2 = CGPoint(
                x: to.x - (next.x - from.x) * 0.15,
                y: to.y - (next.y - from.y) * 0.15
            )
            path.addCurve(to: to, control1: controlPoint1, control2: controlPoint2)
        } else {
            // Simple quadratic curve for edge cases
            let midPoint = CGPoint(
                x: (from.x + to.x) / 2,
                y: (from.y + to.y) / 2
            )
            path.addQuadCurve(to: to, control: midPoint)
        }
        
        let style = isInterpolated ?
            StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round, lineJoin: .round, dash: [lineWidth * 2, lineWidth]) :
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        
        context.stroke(path, with: .color(color.opacity(opacity)), style: style)
    }
    
    private func calculateAccelerationColor(baseColor: Color, acceleration: Float) -> Color {
        // Normalize acceleration (-1 to 1 range for color mapping)
        let normalizedAccel = max(-1, min(1, acceleration / 10.0))
        
        // Convert to UIColor for HSB manipulation
        let uiColor = UIColor(baseColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Shift hue based on acceleration
        // Negative acceleration (deceleration) = cooler (shift toward blue)
        // Positive acceleration = warmer (shift toward yellow/red)
        let hueShift = CGFloat(normalizedAccel) * 0.08 // Max 8% hue shift
        var newHue = hue + hueShift
        
        // Keep hue in valid range [0, 1]
        if newHue < 0 { newHue += 1 }
        if newHue > 1 { newHue -= 1 }
        
        // Slightly increase saturation for acceleration
        let newSaturation = min(1.0, saturation + abs(CGFloat(normalizedAccel)) * 0.15)
        
        return Color(UIColor(hue: newHue, saturation: newSaturation, brightness: brightness, alpha: alpha))
    }
    
    private func calculateSegmentOpacity(index: Int, total: Int, showFullPath: Bool) -> Double {
        if showFullPath {
            // Full path shown - use subtle gradient from oldest to newest
            return 0.4 + 0.4 * Double(index) / Double(max(total - 1, 1))
        } else {
            // Progressive reveal - emphasize recent segments
            let recencyFactor = Double(index) / Double(max(total - 1, 1))
            return 0.3 + 0.7 * recencyFactor
        }
    }
    
    private func drawPowerSpot(context: GraphicsContext,
                              at point: CGPoint,
                              color: Color,
                              intensity: CGFloat) {
        // Outer glow with radial gradient
        let glowGradient = Gradient(colors: [
            color.opacity(0.6 * Double(intensity)),
            color.opacity(0.3 * Double(intensity)),
            color.opacity(0)
        ])
        
        context.fill(
            Circle().path(in: CGRect(
                x: point.x - powerSpotGlowRadius,
                y: point.y - powerSpotGlowRadius,
                width: powerSpotGlowRadius * 2,
                height: powerSpotGlowRadius * 2
            )),
            with: .radialGradient(
                glowGradient,
                center: point,
                startRadius: 0,
                endRadius: powerSpotGlowRadius
            )
        )
        
        // Inner bright spot
        context.fill(
            Circle().path(in: CGRect(
                x: point.x - powerSpotRadius/2,
                y: point.y - powerSpotRadius/2,
                width: powerSpotRadius,
                height: powerSpotRadius
            )),
            with: .color(color)
        )
        
        // Center highlight
        context.fill(
            Circle().path(in: CGRect(
                x: point.x - 2,
                y: point.y - 2,
                width: 4,
                height: 4
            )),
            with: .color(.white.opacity(0.9))
        )
    }
    
    private func drawCurrentPosition(context: GraphicsContext,
                                    at point: CGPoint,
                                    color: Color) {
        // Pulsing current position indicator
        context.fill(
            Circle().path(in: CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            )),
            with: .color(color)
        )
        
        // Inner white dot
        context.fill(
            Circle().path(in: CGRect(
                x: point.x - 2,
                y: point.y - 2,
                width: 4,
                height: 4
            )),
            with: .color(.white.opacity(0.9))
        )
    }
}

// Color tokens and hex initializer live in DesignSystem/Colors.swift