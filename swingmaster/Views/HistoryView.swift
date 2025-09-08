//
//  HistoryView.swift
//  swingmaster
//
//  Phase 1: Simple history list backed by mock data.
//

import SwiftUI

/// History list backed by saved sessions (newest first).
struct HistoryView: View {
    let sessions: [Session]
    let onSelect: (Session) -> Void

    init(sessions: [Session], onSelect: @escaping (Session) -> Void) {
        self.sessions = sessions
        self.onSelect = onSelect
    }

    var body: some View {
        List(sessions) { session in
            Button(action: { onSelect(session) }) {
                HistoryRow(session: session)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.black)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
    }
}

/// Visual representation of a single session row.
private struct HistoryRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 40)
                Image(uiImage: VideoStorage.generateThumbnail(for: session.videoURL, at: 1.0) ?? UIImage())
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 40)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateString(session.date))
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .semibold))
                Text("\(session.shotCount) shots")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.dateString(session.date)), \(session.shotCount) shots")
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

#Preview("HistoryView") {
    let fake = Session(id: UUID(), date: Date(), videoPath: "/tmp/preview.mov", shotCount: 4)
    return HistoryView(sessions: [fake]) { _ in }
        .preferredColorScheme(.dark)
}


