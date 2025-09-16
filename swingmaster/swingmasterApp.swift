//
//  swingmasterApp.swift
//  swingmaster
//
//  Created by ruinan zhang on 2025/9/6.
//

import SwiftUI
import Foundation

@main
struct swingmasterApp: App {
    init() {
        NetworkPermissionWarmer.trigger()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Warms up the system cellular data permission by issuing a tiny HEAD request
/// as early as possible on app launch. This surfaces the "Allow to use wireless data"
/// prompt immediately, instead of later during video upload/analysis.
///
/// Usage: Called once from `swingmasterApp.init()`.
private enum NetworkPermissionWarmer {
    /// Triggers a lightweight network request to prompt cellular data permission.
    /// - Note: Uses HEAD to minimize data usage and completes silently.
    static func trigger() {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, _, _ in } .resume()
    }
}
