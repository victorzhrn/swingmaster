import SwiftUI

struct PageIndicator: View {
    let currentPage: Int
    let pageCount: Int
    
    var style: IndicatorStyle = .line
    
    enum IndicatorStyle {
        case dots
        case line
    }
    
    var body: some View {
        switch style {
        case .dots:
            dotsIndicator
        case .line:
            lineIndicator
        }
    }
    
    private var dotsIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? TennisColors.tennisGreen : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }
    
    private var lineIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<pageCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == currentPage ? TennisColors.tennisGreen : Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
            }
        }
    }
}