import SwiftUI

struct MarkdownContent: View {
    let markdown: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sections = markdown.components(separatedBy: "\n\n")
            
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                parseSection(section)
            }
        }
    }
    
    @ViewBuilder
    private func parseSection(_ section: String) -> some View {
        let lines = section.components(separatedBy: "\n")
        
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                parseLine(line)
            }
        }
    }
    
    @ViewBuilder
    private func parseLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("## ") {
            Text(trimmed.dropFirst(3))
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 8)
        } else if trimmed.hasPrefix("### ") {
            Text(trimmed.dropFirst(4))
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("✓") {
            HStack(alignment: .top, spacing: 8) {
                Text("✓")
                    .foregroundColor(TennisColors.tennisGreen)
                    .font(.system(size: 16, weight: .bold))
                Text(trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 15))
            }
        } else if trimmed.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 15))
                Text(trimmed.dropFirst(2))
                    .font(.system(size: 15))
            }
        } else if !trimmed.isEmpty {
            Text(trimmed)
                .font(.system(size: 15))
                .lineSpacing(4)
        }
    }
}