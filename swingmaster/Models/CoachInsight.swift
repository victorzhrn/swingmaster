import Foundation

struct CoachInsight: Identifiable {
    let id = UUID()
    let tag: String
    let issueTitle: String
    let shortDescription: String
    let markdownContent: String
    let videoReference: VideoRef?
}

struct VideoRef {
    let youtubeId: String
    let timestamp: Int
    let title: String
}