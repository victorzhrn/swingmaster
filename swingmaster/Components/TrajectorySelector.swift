//
//  TrajectorySelector.swift
//  swingmaster
//
//  Controls for selecting trajectory types and options.
//

import SwiftUI

struct TrajectorySelector: View {
    @Binding var enabledTrajectories: Set<TrajectoryType>
    @Binding var trajectoryOptions: TrajectoryOptions
    @State private var isExpanded = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "scribble.variable")
                    if !enabledTrajectories.isEmpty {
                        Text("\(enabledTrajectories.count)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(TennisColors.tennisGreen))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .clipShape(Capsule())
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(TrajectoryType.allCases) { type in
                        Button(action: { toggle(type) }) {
                            HStack {
                                Image(systemName: icon(for: type))
                                    .frame(width: 20)
                                Text(type.rawValue)
                                    .font(.system(size: 13))
                                Spacer()
                                if enabledTrajectories.contains(type) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Divider().padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Fill Gaps", isOn: Binding(
                            get: { trajectoryOptions.fillGaps },
                            set: { newValue in
                                trajectoryOptions = TrajectoryOptions(
                                    fillGaps: newValue,
                                    maxGapSeconds: trajectoryOptions.maxGapSeconds,
                                    smooth: trajectoryOptions.smooth,
                                    smoothingWindow: trajectoryOptions.smoothingWindow
                                )
                            }
                        )).font(.system(size: 12))
                        Toggle("Smooth Path", isOn: Binding(
                            get: { trajectoryOptions.smooth },
                            set: { newValue in
                                trajectoryOptions = TrajectoryOptions(
                                    fillGaps: trajectoryOptions.fillGaps,
                                    maxGapSeconds: trajectoryOptions.maxGapSeconds,
                                    smooth: newValue,
                                    smoothingWindow: trajectoryOptions.smoothingWindow
                                )
                            }
                        )).font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .padding(.vertical, 8)
                .frame(width: 200)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private func toggle(_ type: TrajectoryType) {
        if enabledTrajectories.contains(type) { enabledTrajectories.remove(type) } else { enabledTrajectories.insert(type) }
    }
    private func icon(for type: TrajectoryType) -> String {
        switch type {
        case .rightWrist, .leftWrist: return "hand.raised"
        case .rightElbow, .leftElbow: return "figure.arms.open"
        case .rightShoulder, .leftShoulder: return "person"
        case .racketCenter: return "circle"
        case .ballCenter: return "circle.fill"
        }
    }
}


