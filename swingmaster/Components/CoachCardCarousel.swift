import SwiftUI

struct CoachCardCarousel: View {
    let insights: [CoachInsight]
    @State private var currentPage = 0
    @Binding var selectedInsight: CoachInsight?
    
    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(insights.indices, id: \.self) { index in
                CoachCard(
                    category: insights[index].tag,
                    insight: formatInsightText(insights[index]),
                    issueTitle: insights[index].issueTitle,
                    showPageIndicator: true,
                    currentPage: currentPage,
                    pageCount: insights.count
                )
                .padding(.horizontal, Spacing.screenMargin)
                .tag(index)
                .onTapGesture {
                    selectedInsight = insights[index]
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(height: 140) // Slightly increased to accommodate integrated indicator
    }
    
    private func formatInsightText(_ insight: CoachInsight) -> String {
        insight.shortDescription
    }
}