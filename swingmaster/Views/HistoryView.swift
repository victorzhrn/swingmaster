//
//  HistoryView.swift
//  swingmaster
//
//  Phase 1: Simple history list backed by mock data.
//

import SwiftUI

/// Represents a previously recorded practice session (mocked in Phase 1).
/// - Properties:
///   - id: Stable identifier
///   - date: Human-friendly date label (e.g., "Today 2:30 PM")
///   - shotCount: Number of detected swings
///   - videoURL: Placeholder string path/url
///   - thumbnailSystemName: SF Symbol used as the thumbnail placeholder
struct MockSession: Identifiable {
    let id = UUID()
    let date: String
    let shotCount: Int
    let videoURL: String
    let thumbnailSystemName: String
}

/// Supplies mock sessions for Phase 1 UI.
enum MockDataProvider {
    static let sessions: [MockSession] = [
        MockSession(date: "Today 2:30 PM", shotCount: 5, videoURL: "mock://today", thumbnailSystemName: "video"),
        MockSession(date: "Yesterday", shotCount: 3, videoURL: "mock://yesterday", thumbnailSystemName: "video"),
        MockSession(date: "Jan 21", shotCount: 8, videoURL: "mock://jan21", thumbnailSystemName: "video"),
        MockSession(date: "Jan 20", shotCount: 12, videoURL: "mock://jan20", thumbnailSystemName: "video"),
        MockSession(date: "Jan 18", shotCount: 4, videoURL: "mock://jan18", thumbnailSystemName: "video")
    ]
}

/// Phase 1 History list.
/// Displays 5 hardcoded sessions; selecting a row triggers `onSelect`.
/// - Usage:
/// ```swift
/// HistoryView { session in
///     // Navigate to analysis with `session`
/// }
/// ```
struct HistoryView: View {
    let sessions: [MockSession]
    let onSelect: (MockSession) -> Void

    init(sessions: [MockSession] = MockDataProvider.sessions, onSelect: @escaping (MockSession) -> Void = { _ in }) {
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
    let session: MockSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 40)
                Image(systemName: session.thumbnailSystemName)
                    .foregroundColor(.white)
                    .opacity(0.9)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.date)
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
        .accessibilityLabel("\(session.date), \(session.shotCount) shots")
    }
}

#Preview("HistoryView") {
    HistoryView()
        .preferredColorScheme(.dark)
}


