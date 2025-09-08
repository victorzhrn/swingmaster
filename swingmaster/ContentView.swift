//
//  ContentView.swift
//  swingmaster
//
//  Created by ruinan zhang on 2025/9/6.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView { _ in
            // TODO: Navigate to AnalysisView with recorded URL in later phase
        }
    }
}

#Preview("ContentView") {
    ContentView()
        .preferredColorScheme(.dark)
}
