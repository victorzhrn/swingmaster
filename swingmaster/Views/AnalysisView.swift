//
//  AnalysisView.swift
//  swingmaster
//
//  Accessible analysis screen with video placeholder, timeline strip, chips row,
//  and an insight card that updates with the selected shot.
//

import SwiftUI

struct AnalysisView: View {
    let videoURL: URL?
    let duration: Double
    let shots: [MockShot]

    @State private var selectedShotID: MockShot.ID?
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Real video when available, otherwise placeholder
            Group {
                if let url = videoURL {
                    VideoPlayerView(url: url, currentTime: $currentTime, isPlaying: $isPlaying)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .accessibilityLabel("Video player")
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        VStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.9))
                            Text(timeString(currentTime) + " / " + timeString(duration))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .frame(height: 320)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Video player")
                    .accessibilityValue("Time \(timeString(currentTime)) of \(timeString(duration))")
                }
            }

            // Timeline Strip (visual + adjustable)
            TimelineStrip(duration: duration, shots: shots, selectedShotID: $selectedShotID, currentTime: $currentTime)
                .padding(.horizontal, 16)

            // Chips Row (primary large tap targets) with prev/next
            ShotChipsRow(shots: shots, selectedShotID: $selectedShotID, onPrev: selectPrev, onNext: selectNext)

            // Insight Card
            insightCard
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if selectedShotID == nil, let first = shots.first { selectedShotID = first.id; currentTime = first.time }
        }
        .onChange(of: selectedShotID) { _, newID in
            // Seek video when selection changes
            if let id = newID, let shot = shots.first(where: { $0.id == id }) {
                currentTime = shot.time
            }
        }
        .onChange(of: currentTime) { _, t in
            // Auto-advance selection while playing, with hysteresis between markers
            guard isPlaying, !shots.isEmpty else { return }
            guard let currentIndex = currentSelectedIndexOrNearest(to: t) else { return }
            let idx = currentIndex
            // Decide if we cross midpoint to next or previous
            if idx < shots.count - 1 {
                let midToNext = (shots[idx].time + shots[idx + 1].time) / 2
                if t >= midToNext - 0.05 { selectedShotID = shots[idx + 1].id }
            }
            if idx > 0 {
                let midToPrev = (shots[idx - 1].time + shots[idx].time) / 2
                if t < midToPrev + 0.05 { selectedShotID = shots[idx - 1].id }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var insightCard: some View {
        let selected = shots.first(where: { $0.id == selectedShotID })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selected?.type.accessibleName ?? "Shot")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("Score: " + String(format: "%.1f", selected?.score ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }

            Text(selected?.issue ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Placeholder for overlay description
            Text("Visual overlay highlights contact and ideal point")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insight. \(selected?.type.accessibleName ?? "Shot"). Score \(String(format: "%.1f", selected?.score ?? 0)). \(selected?.issue ?? "")")
    }

    // MARK: - Actions

    private func selectPrev() {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = max(idx - 1, 0)
        let shot = shots[newIndex]
        selectedShotID = shot.id
        currentTime = shot.time
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func selectNext() {
        guard let id = selectedShotID, let idx = shots.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = min(idx + 1, shots.count - 1)
        let shot = shots[newIndex]
        selectedShotID = shot.id
        currentTime = shot.time
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func timeString(_ t: Double) -> String {
        let seconds = Int(t.rounded())
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func currentSelectedIndexOrNearest(to time: Double) -> Int? {
        if let sel = selectedShotID, let idx = shots.firstIndex(where: { $0.id == sel }) { return idx }
        // Fallback: nearest by absolute time
        let pairs = shots.enumerated().map { ($0.offset, abs($0.element.time - time)) }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }
}

#Preview("AnalysisView") {
    let shots = Array<MockShot>.sampleShots(duration: 92)
    return AnalysisView(videoURL: nil, duration: 92, shots: shots)
}


