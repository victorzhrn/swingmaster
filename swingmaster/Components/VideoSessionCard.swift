//
//  VideoSessionCard.swift
//  swingmaster
//
//  Video-primary session card with interactive shot dots
//

import SwiftUI
import AVKit

struct VideoSessionCard: View {
    let session: Session
    @State private var thumbnailImage: UIImage?
    @State private var analysisData: PersistedAnalysis?
    
    private var shots: [MockShot] {
        analysisData?.shots ?? []
    }
    
    private var averageScore: Float {
        guard !shots.isEmpty else { return 0 }
        return shots.map { $0.score }.reduce(0, +) / Float(shots.count)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        GlassContainer(style: .medium, cornerRadius: 16) {
            VStack(spacing: 0) {
                // Video thumbnail
                ZStack {
                    if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [Color.black.opacity(0), Color.black.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            )
                    }
                    
                    // Play button overlay (smaller and subtler)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                
                // Info bar
                HStack {
                    Text(dateFormatter.string(from: session.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !shots.isEmpty {
                        HStack(spacing: 12) {
                            // Average score
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(TennisColors.tennisYellow)
                                Text(String(format: "%.1f", averageScore))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .tennisMetricStyle()
                            }
                            
                            // Shot count
                            Text("\(shots.count) shots")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.vertical, Spacing.small)
                .background(Color.clear)
            }
        }
        .onAppear {
            loadAnalysisData()
            updateThumbnail(for: shots.first?.time ?? 1.0)
        }
    }
    
    private func loadAnalysisData() {
        analysisData = AnalysisStore.load(videoURL: session.videoURL)
    }
    
    private func updateThumbnail(for time: Double) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = VideoStorage.generateThumbnail(for: session.videoURL, at: time)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.thumbnailImage = image
                }
            }
        }
    }
}

#Preview {
    VideoSessionCard(
        session: Session(
            id: UUID(),
            date: Date(),
            videoPath: "sample.mov",
            shotCount: 5
        )
    )
    .padding()
    .preferredColorScheme(.dark)
}
