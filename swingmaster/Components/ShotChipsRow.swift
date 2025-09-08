//
//  ShotChipsRow.swift
//  swingmaster
//
//  Horizontally scrollable row of large tap targets representing shots.
//  Provides Prev/Next controls and VoiceOver-friendly labels.
//

import SwiftUI

struct ShotChipsRow: View {
    let shots: [MockShot]
    @Binding var selectedShotID: MockShot.ID?
    let onPrev: () -> Void
    let onNext: () -> Void

    private let chipHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: chipHeight)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Previous shot")

            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        ForEach(shots) { shot in
                            let isSelected = shot.id == selectedShotID
                            Button(action: { select(shot, proxy: proxy) }) {
                                HStack(spacing: 6) {
                                    Text(shot.type.shortLabel)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    Text(String(format: "%.1f", shot.score))
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .frame(height: chipHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSelected ? shot.type.accentColor : Color.white.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                        )
                                )
                            }
                            .id(shot.id)
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(shot.type.accessibleName), score \(String(format: "%.1f", shot.score))")
                            .accessibilityHint("Double tap to select shot")
                        }
                    }
                    .onChange(of: selectedShotID) { _, newID in
                        if let id = newID { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: chipHeight)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Next shot")
        }
        .padding(.horizontal, 12)
    }

    private func select(_ shot: MockShot, proxy: ScrollViewProxy) {
        selectedShotID = shot.id
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation { proxy.scrollTo(shot.id, anchor: .center) }
    }
}

#Preview("ShotChipsRow") {
    StatefulPreviewWrapper3(Array<MockShot>.sampleShots(duration: 90), UUID? .none, 0) { shots, sel, _ in
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                ShotChipsRow(shots: shots.wrappedValue, selectedShotID: sel, onPrev: {}, onNext: {})
                TimelineStrip(duration: 90, shots: shots.wrappedValue, selectedShotID: sel, currentTime: .constant(0))
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}


