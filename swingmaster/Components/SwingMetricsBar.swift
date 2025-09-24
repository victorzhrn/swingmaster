//
//  SwingMetricsBar.swift
//  swingmaster
//
//  Compact metrics bar overlay for full-screen video experience.
//

import SwiftUI

struct SwingMetricsBar: View {
    let shot: Shot?
    @State private var isExpanded: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var metrics: SegmentMetrics? {
        shot?.segmentMetrics
    }
    
    // Metric data structure for flexible grid
    private struct MetricData: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
        let color: Color
    }
    
    // All available metrics in display order
    private var allMetrics: [MetricData] {
        [
            MetricData(
                icon: "gauge",
                label: "Peak Speed",
                value: "\(Int(metrics?.peakAngularVelocity ?? 0)) rad/s",
                color: TennisColors.clayOrange
            ),
            MetricData(
                icon: "arrow.triangle.2.circlepath", 
                label: "Shoulder",
                value: "\(Int(metrics?.backswingAngle ?? 0))°",
                color: .blue
            ),
            MetricData(
                icon: "target",
                label: "Contact",
                value: "\(Int((metrics?.contactPoint.y ?? 0) * 100))%",
                color: TennisColors.aceGreen
            ),
            MetricData(
                icon: "arrow.up.right.circle",
                label: "Follow",
                value: "\(Int((metrics?.followThroughHeight ?? 0) * 100))%",
                color: .purple
            ),
            MetricData(
                icon: "checkmark.seal.fill",
                label: "Quality", 
                value: "\(Int((metrics?.averageConfidence ?? 0) * 100))%",
                color: (metrics?.averageConfidence ?? 0) > 0.7 ? TennisColors.aceGreen : TennisColors.tennisYellow
            )
        ]
    }
    
    var body: some View {
        Group {
            if isExpanded {
                expandedView()
            } else {
                compactView()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded) // Standard .quick spring
    }
    
    private func compactView() -> some View {
        HStack(spacing: 10) {
            // Shot type
            Text(shot?.type.accessibleName.uppercased() ?? "SHOT")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("•")
                .foregroundColor(.secondary)
            
            // Inline metrics with consistent opacity
            Group {
                metricPill(icon: "gauge", 
                          value: "\(Int(metrics?.peakAngularVelocity ?? 0))",
                          color: TennisColors.clayOrange)
                
                metricPill(icon: "arrow.triangle.2.circlepath",
                          value: "\(Int(metrics?.backswingAngle ?? 0))°",
                          color: .blue)
                
                metricPill(icon: "target",
                          value: "\(Int((metrics?.contactPoint.y ?? 0) * 100))%",
                          color: TennisColors.aceGreen)
                
                metricPill(icon: "arrow.up.right.circle",
                          value: "\(Int((metrics?.followThroughHeight ?? 0) * 100))%",
                          color: .purple)
            }
            
            Spacer()
            
            // Expand button
            Image(systemName: "chevron.down.circle")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 40) // Reduced from 44 for better video visibility
        .background(.ultraThinMaterial) // Subtle glass effect
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16) // Consistent 16pt margins
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { // Standard .quick spring
                isExpanded = true
            }
        }
    }
    
    @ViewBuilder
    private func metricPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
    
    private func expandedView() -> some View {
        VStack(spacing: 0) {
            // Header - Consistent with compact view styling
            HStack {
                Text("\(shot?.type.accessibleName.uppercased() ?? "SHOT") ANALYSIS")
                    .font(.system(size: 13, weight: .semibold)) // Match compact view size
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20)) // Slightly smaller for consistency
                        .foregroundColor(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Close metrics")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Subtle divider with consistent opacity
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
            
            // N×2 metrics grid with proper spacing
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 24),
                GridItem(.flexible(), spacing: 24)
            ], spacing: 12) {
                ForEach(allMetrics, id: \.id) { metric in
                    metricCard(
                        icon: metric.icon,
                        label: metric.label,
                        value: metric.value,
                        color: metric.color
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial) // Match compact view glass level
        .overlay(
            RoundedRectangle(cornerRadius: 20) // Match compact view corner radius
                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16) // Match compact view margins
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
    
    @ViewBuilder
    private func metricCard(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) { // Design system small spacing
            // Icon with proper sizing and rendering
            Image(systemName: icon)
                .font(.system(size: 17)) // .small icon size from design principles
                .foregroundColor(color)
                .frame(width: 20)
                .symbolRenderingMode(.hierarchical)
            
            VStack(alignment: .leading, spacing: 2) { // Tight spacing for related content
                Text(label)
                    .font(.system(size: 11, weight: .medium)) // .caption2 from design principles
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced)) // Smaller but still readable
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0) // Allow flexible sizing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4) // Micro spacing for breathing room
    }
    
    // Legacy metricRow for compact view compatibility
    @ViewBuilder
    private func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        metricCard(icon: icon, label: label, value: value, color: color)
    }
}

#Preview {
    SwingMetricsBar(shot: Array<Shot>.sampleShots(duration: 10).first)
        .preferredColorScheme(.dark)
}