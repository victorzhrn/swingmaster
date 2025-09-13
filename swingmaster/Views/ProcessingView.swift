//
//  ProcessingView.swift
//  swingmaster
//
//  Runs VideoProcessor on a given URL and shows progress. On completion,
//  maps results to AnalysisView-compatible data and calls onComplete.
//

import SwiftUI

struct ProcessingView: View {
    let videoURL: URL
    let geminiAPIKey: String
    let onComplete: (_ results: [AnalysisResult]) -> Void
    let onCancel: () -> Void

    @StateObject private var processorHolder = ProcessorHolder()

    var body: some View {
        VStack(spacing: 16) {
            Text("Analyzing Video…")
                .font(.headline)
                .foregroundColor(.white)

            progressBlock

            Button("Cancel") { onCancel() }
                .foregroundColor(.black)
                .frame(height: 44)
                .padding(.horizontal, Spacing.medium)
                .background(TennisColors.tennisYellow)
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .task {
            // Initialize with API key (once)
            if processorHolder.processor == nil {
                processorHolder.processor = VideoProcessor(geminiAPIKey: geminiAPIKey)
            }
            guard let processor = processorHolder.processor else { return }
            let results = await processor.processVideo(videoURL)
            onComplete(results)
        }
    }

    @ViewBuilder
    private var progressBlock: some View {
        if let processor = processorHolder.processor {
            switch processor.state {
            case .extractingPoses(let p):
                ProgressView(value: Double(p))
                    .progressViewStyle(.linear)
                    .tint(.white)
                Text(String(format: "Extracting poses… %.0f%%", Double(p) * 100))
                    .foregroundColor(.white.opacity(0.9))
                    .font(.system(size: 14, weight: .semibold))
            case .calculatingMetrics:
                ind("Calculating metrics…")
            case .detectingSwings:
                ind("Detecting swings…")
            case .validatingSwings(let cur, let total):
                ind("Validating swings… (\(cur)/\(total))")
            case .analyzingSwings(let cur, let total):
                ind("Analyzing swings… (\(cur)/\(total))")
            case .complete:
                EmptyView()
            }
        } else {
            ind("Preparing…")
        }
    }

    private func ind(_ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text(text)
                .foregroundColor(.white.opacity(0.9))
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

private final class ProcessorHolder: ObservableObject {
    @Published var processor: VideoProcessor?
}


