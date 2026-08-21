import SwiftUI

struct MarkdownMessageView: View {
    let text: String
    var fontSize: CGFloat = 14

    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case quote(String)
        case code(String)
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(from: text).enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let line):
            inline(line, size: fontSize + 2, weight: .semibold)
                .padding(.top, 4)
        case .bullet(let line):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(.system(size: fontSize)).foregroundColor(.secondary)
                inline(line, size: fontSize)
            }
            .padding(.leading, 6)
        case .numbered(let number, let line):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number + ".")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(.secondary)
                inline(line, size: fontSize)
            }
            .padding(.leading, 6)
        case .quote(let line):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 3)
                inline(line, size: fontSize)
                    .foregroundColor(.primary.opacity(0.8))
            }
            .padding(.vertical, 2)
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: fontSize - 2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
        case .paragraph(let line):
            inline(line, size: fontSize)
        }
    }

    private func inline(_ markdown: String, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        let attributed = (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
        return Text(attributed)
            .font(.system(size: size, weight: weight))
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func blocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))); quote = [] }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let current = code {
                if line.hasPrefix("```") {
                    blocks.append(.code(current.joined(separator: "\n")))
                    code = nil
                } else {
                    code = current + [rawLine]
                }
                continue
            }
            if line.hasPrefix("```") { flushParagraph(); flushQuote(); code = []; continue }
            if line.isEmpty { flushParagraph(); flushQuote(); continue }
            if line.hasPrefix(">") {
                flushParagraph()
                quote.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()
            if let range = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushParagraph()
                blocks.append(.heading(String(line[range.upperBound...])))
            } else if let range = line.range(of: #"^[-*•]\s+"#, options: .regularExpression) {
                flushParagraph()
                blocks.append(.bullet(String(line[range.upperBound...])))
            } else if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let number = line[..<range.upperBound].trimmingCharacters(in: CharacterSet(charactersIn: ".) "))
                blocks.append(.numbered(number, String(line[range.upperBound...])))
            } else {
                paragraph.append(line)
            }
        }
        if let current = code { blocks.append(.code(current.joined(separator: "\n"))) }
        flushParagraph()
        flushQuote()
        return blocks
    }
}
