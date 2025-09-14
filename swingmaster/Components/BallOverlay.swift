//
//  BallOverlay.swift
//  swingmaster
//
//  Tennis ball detection overlay component
//

import SwiftUI

struct BallOverlay: View {
    let detection: BallDetection?
    
    var body: some View {
        GeometryReader { geo in
            if let detection = detection {
                Circle()
                    .stroke(TennisColors.tennisYellow, lineWidth: 2)
                    .background(
                        Circle()
                            .fill(TennisColors.tennisYellow.opacity(0.2))
                    )
                    .frame(
                        width: detection.boundingBox.width * geo.size.width,
                        height: detection.boundingBox.height * geo.size.height
                    )
                    .position(
                        x: detection.boundingBox.midX * geo.size.width,
                        y: (1 - detection.boundingBox.midY) * geo.size.height
                    )
                    .animation(.smooth(duration: 0.1), value: detection.boundingBox)
            }
        }
        .allowsHitTesting(false)
    }
}