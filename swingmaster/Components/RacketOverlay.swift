//
//  RacketOverlay.swift
//  swingmaster
//
//  Tennis racket detection overlay component
//

import SwiftUI

struct RacketOverlay: View {
    let detection: RacketDetection?
    
    var body: some View {
        GeometryReader { geo in
            if let detection = detection {
                Rectangle()
                    .stroke(TennisColors.tennisYellow, lineWidth: 3)
                    .frame(
                        width: detection.boundingBox.width * geo.size.width,
                        height: detection.boundingBox.height * geo.size.height
                    )
                    .position(
                        x: detection.boundingBox.midX * geo.size.width,
                        y: (1 - detection.boundingBox.midY) * geo.size.height
                    )
                    .overlay(
                        Text("Racket \(Int(detection.confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(TennisColors.tennisYellow)
                            .padding(2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .position(
                                x: detection.boundingBox.minX * geo.size.width + 40,
                                y: (1 - detection.boundingBox.maxY) * geo.size.height - 10
                            )
                    )
                    .animation(.smooth(duration: 0.1), value: detection.boundingBox)
            }
        }
        .allowsHitTesting(false)
    }
}