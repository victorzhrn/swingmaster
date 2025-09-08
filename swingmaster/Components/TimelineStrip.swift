//
//  TimelineStrip.swift
//  swingmaster
//
//  Accessible timeline strip showing shot markers mapped to video time.
//  - 56pt interaction band
//  - Snap-to-nearest marker selection
//  - VoiceOver: Adjustable with Previous/Next custom actions
//

import SwiftUI
import UIKit

struct TimelineStrip: View {
    let duration: Double
    let shots: [MockShot]
    @Binding var selectedShotID: MockShot.ID?
    @Binding var currentTime: Double

    /// Minimum interactive width around a marker to ensure accessibility.
    private let minInteractiveRadius: CGFloat = 16 // 32pt total diameter
    private let bandHeight: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Glass background strip
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                // Timeline axis and markers
                ZStack(alignment: .leading) {
                    // Baseline axis
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 3)
                        .offset(y: -2)

                    // Markers
                    ForEach(shots) { shot in
                        let xPos = xPosition(for: shot.time, width: geo.size.width)
                        let isSelected = shot.id == selectedShotID
                        markerView(for: shot, selected: isSelected)
                            .position(x: xPos, y: geo.size.height / 2)
                            .contentShape(Rectangle().inset(by: -minInteractiveRadius))
                            .onTapGesture {
                                select(shot)
                            }
                            .accessibilityElement()
                            .accessibilityLabel("\(shot.type.accessibleName), score \(String(format: "%.1f", shot.score)) at \(formattedTime(shot.time))")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: bandHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        // Snap to nearest marker at drag location
                        let x = value.location.x
                        if let nearest = nearestShot(atX: x, totalWidth: geo.size.width) {
                            select(nearest)
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Shot timeline")
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                guard let currentIndex = shots.firstIndex(where: { $0.id == selectedShotID }) else {
                    if let first = shots.first { select(first) }
                    return
                }
                switch direction {
                case .increment:
                    let next = min(currentIndex + 1, shots.count - 1)
                    select(shots[next])
                case .decrement:
                    let prev = max(currentIndex - 1, 0)
                    select(shots[prev])
                default:
                    break
                }
            }
        }
        .frame(height: bandHeight)
    }

    private func xPosition(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clamped = max(0, min(time, duration))
        return CGFloat(clamped / duration) * max(1, width - 24) + 12 // padding
    }

    private func nearestShot(atX x: CGFloat, totalWidth: CGFloat) -> MockShot? {
        guard !shots.isEmpty else { return nil }
        let pairs = shots.map { shot -> (MockShot, CGFloat) in
            let pos = xPosition(for: shot.time, width: totalWidth)
            return (shot, abs(pos - x))
        }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }

    private func select(_ shot: MockShot) {
        selectedShotID = shot.id
        currentTime = shot.time
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private var accessibilityValue: String {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else {
            return "No shot selected"
        }
        return "Shot \(idx + 1) of \(shots.count)"
    }

    @ViewBuilder
    private func markerView(for shot: MockShot, selected: Bool) -> some View {
        let baseSize: CGFloat = selected ? 20 : 12
        ZStack {
            Circle()
                .fill(shot.type.accentColor.opacity(0.9))
                .frame(width: baseSize, height: baseSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(selected ? 0.9 : 0.6), lineWidth: selected ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)

            if selected {
                Text(shot.type.shortLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .frame(minWidth: minInteractiveRadius * 2, minHeight: minInteractiveRadius * 2)
    }

    private func formattedTime(_ t: Double) -> String {
        let seconds = Int(t.rounded())
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview("TimelineStrip") {
    StatefulPreviewWrapper3(Array<MockShot>.sampleShots(duration: 90), UUID? .none, 0.0) { shots, selected, time in
        VStack {
            TimelineStrip(duration: 90, shots: shots.wrappedValue, selectedShotID: selected, currentTime: time)
                .padding()
        }
        .preferredColorScheme(.dark)
        .background(Color.black)
    }
}

// MARK: - Stateful preview helper

struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State var value1: Value
    @ViewBuilder var content: (_ binding: Binding<Value>) -> Content

    init(_ value1: Value, @ViewBuilder content: @escaping (_ binding: Binding<Value>) -> Content) {
        self._value1 = State(initialValue: value1)
        self.content = content
    }

    var body: some View { content($value1) }
}

// Overload for 3 values used above
struct StatefulPreviewWrapper3<V1, V2, V3, Content: View>: View {
    @State var v1: V1
    @State var v2: V2
    @State var v3: V3
    let contentBuilder: (_ b1: Binding<V1>, _ b2: Binding<V2>, _ b3: Binding<V3>) -> Content

    init(_ v1: V1, _ v2: V2, _ v3: V3, @ViewBuilder content: @escaping (_ b1: Binding<V1>, _ b2: Binding<V2>, _ b3: Binding<V3>) -> Content) {
        self._v1 = State(initialValue: v1)
        self._v2 = State(initialValue: v2)
        self._v3 = State(initialValue: v3)
        self.contentBuilder = content
    }

    var body: some View {
        contentBuilder($v1, $v2, $v3)
    }
}


