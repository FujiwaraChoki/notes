import AppKit
import Markdown

struct ImageReference {
    let range: NSRange
    let source: String
}

struct MarkdownStyle {
    let bodyFont: NSFont
    let headingFonts: [NSFont] // H1, H2, H3
    let monospaceFont: NSFont
    let textColor: NSColor
    let dimmedColor: NSColor
    let linkColor: NSColor
    let blockQuoteColor: NSColor
    let codeBackground: NSColor
    let lineSpacing: CGFloat

    static let `default` = MarkdownStyle(
        bodyFont: .systemFont(ofSize: 15, weight: .regular),
        headingFonts: [
            .systemFont(ofSize: 28, weight: .bold),   // H1
            .systemFont(ofSize: 22, weight: .bold),   // H2
            .systemFont(ofSize: 18, weight: .semibold) // H3
        ],
        monospaceFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
        textColor: .labelColor,
        dimmedColor: .tertiaryLabelColor,
        linkColor: .linkColor,
        blockQuoteColor: .secondaryLabelColor,
        codeBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.15),
        lineSpacing: 4
    )
}

class MarkdownFormatter {
    let style: MarkdownStyle
    private(set) var lastImageReferences: [ImageReference] = []

    init(style: MarkdownStyle = .default) {
        self.style = style
    }

    func format(_ text: String) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)

        // Base paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = style.lineSpacing

        // Default attributes
        attributed.addAttributes([
            .font: style.bodyFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraphStyle,
        ], range: fullRange)

        // Parse markdown
        let document = Document(parsing: text)
        let lineOffsets = computeLineOffsets(text)

        var walker = FormattingWalker(
            attributed: attributed,
            source: text,
            lineOffsets: lineOffsets,
            style: style
        )
        walker.visit(document)
        lastImageReferences = walker.imageReferences

        return attributed
    }

    private func computeLineOffsets(_ text: String) -> [Int] {
        // Build an array where index i is the UTF-16 offset of the start of line (i+1)
        // Line numbers in swift-markdown are 1-based
        var offsets: [Int] = [0] // line 1 starts at UTF-16 offset 0
        var utf16Offset = 0
        for char in text {
            let charLen = String(char).utf16.count
            if char == "\n" {
                utf16Offset += charLen
                offsets.append(utf16Offset)
            } else {
                utf16Offset += charLen
            }
        }
        return offsets
    }
}

// MARK: - FormattingWalker

private struct FormattingWalker: MarkupWalker {
    let attributed: NSMutableAttributedString
    let source: String
    let lineOffsets: [Int]
    let style: MarkdownStyle
    var imageReferences: [ImageReference] = []

    init(
        attributed: NSMutableAttributedString,
        source: String,
        lineOffsets: [Int],
        style: MarkdownStyle
    ) {
        self.attributed = attributed
        self.source = source
        self.lineOffsets = lineOffsets
        self.style = style
    }

    // Convert SourceRange to NSRange
    private func nsRange(for markup: any Markup) -> NSRange? {
        guard let range = markup.range else { return nil }

        let startLine = range.lowerBound.line - 1 // 0-based
        let endLine = range.upperBound.line - 1

        guard startLine >= 0, startLine < lineOffsets.count,
              endLine >= 0, endLine < lineOffsets.count else { return nil }

        // swift-markdown columns are 1-based UTF-8 byte offsets
        let startCol = range.lowerBound.column - 1
        let endCol = range.upperBound.column - 1

        let lineStartUTF16 = lineOffsets[startLine]
        let lineEndUTF16 = lineOffsets[endLine]

        // Convert UTF-8 column offsets to UTF-16
        let startUTF16 = lineStartUTF16 + utf8ColToUTF16(line: startLine, col: startCol)
        let endUTF16 = lineEndUTF16 + utf8ColToUTF16(line: endLine, col: endCol)

        let location = startUTF16
        let length = endUTF16 - startUTF16

        guard location >= 0, length >= 0, location + length <= attributed.length else { return nil }

        return NSRange(location: location, length: length)
    }

    private func utf8ColToUTF16(line: Int, col: Int) -> Int {
        guard line < lineOffsets.count else { return col }

        let lineStart: String.Index
        let utf16LineOffset = lineOffsets[line]
        lineStart = source.utf16.index(source.utf16.startIndex, offsetBy: utf16LineOffset, limitedBy: source.utf16.endIndex) ?? source.utf16.endIndex

        // Walk col UTF-8 bytes from line start and count UTF-16 units
        let lineStartUTF8 = lineStart.samePosition(in: source.utf8) ?? source.utf8.startIndex
        var utf8Idx = lineStartUTF8
        var utf16Count = 0
        var utf8Count = 0

        while utf8Count < col && utf8Idx < source.utf8.endIndex {
            let byte = source.utf8[utf8Idx]
            let charLen: Int
            if byte < 0x80 { charLen = 1 }
            else if byte < 0xE0 { charLen = 2 }
            else if byte < 0xF0 { charLen = 3 }
            else { charLen = 4 }

            let utf16Len = charLen <= 3 ? 1 : 2
            utf8Count += charLen
            utf16Count += utf16Len

            // Advance by charLen UTF-8 bytes
            for _ in 0..<charLen {
                guard utf8Idx < source.utf8.endIndex else { break }
                utf8Idx = source.utf8.index(after: utf8Idx)
            }
        }

        return utf16Count
    }

    // MARK: - Heading

    mutating func visitHeading(_ heading: Heading) {
        guard let range = nsRange(for: heading) else {
            descendInto(heading)
            return
        }

        let level = min(heading.level, 3)
        let font = style.headingFonts[level - 1]
        attributed.addAttribute(.font, value: font, range: range)

        // Dim the # prefix
        let text = attributed.string as NSString
        let lineText = text.substring(with: range)
        if let hashEnd = lineText.firstIndex(of: " ") {
            let hashCount = lineText.distance(from: lineText.startIndex, to: hashEnd) + 1 // include space
            let dimRange = NSRange(location: range.location, length: hashCount)
            if dimRange.location + dimRange.length <= attributed.length {
                attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: dimRange)
            }
        }

        descendInto(heading)
    }

    // MARK: - Strong (Bold)

    mutating func visitStrong(_ strong: Strong) {
        guard let range = nsRange(for: strong) else {
            descendInto(strong)
            return
        }

        // Apply bold trait to existing font
        applyFontTrait(.boldFontMask, in: range)

        // Dim ** delimiters
        dimDelimiters(in: range, prefix: "**", suffix: "**")

        descendInto(strong)
    }

    // MARK: - Emphasis (Italic)

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        guard let range = nsRange(for: emphasis) else {
            descendInto(emphasis)
            return
        }

        applyFontTrait(.italicFontMask, in: range)
        dimDelimiters(in: range, prefix: "*", suffix: "*")

        descendInto(emphasis)
    }

    // MARK: - Inline Code

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = nsRange(for: inlineCode) else { return }

        attributed.addAttribute(.font, value: style.monospaceFont, range: range)
        attributed.addAttribute(.backgroundColor, value: style.codeBackground, range: range)

        // Dim backticks
        dimDelimiters(in: range, prefix: "`", suffix: "`")
    }

    // MARK: - Code Block

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = nsRange(for: codeBlock) else { return }

        attributed.addAttribute(.font, value: style.monospaceFont, range: range)
        attributed.addAttribute(.backgroundColor, value: style.codeBackground, range: range)

        // Dim opening/closing fences
        let text = attributed.string as NSString
        let blockText = text.substring(with: range)
        if blockText.hasPrefix("```") {
            // Find end of first line
            if let newlineIdx = blockText.firstIndex(of: "\n") {
                let prefixLen = blockText.distance(from: blockText.startIndex, to: newlineIdx)
                let dimRange = NSRange(location: range.location, length: prefixLen)
                attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: dimRange)
            }
            // Find closing fence
            if blockText.hasSuffix("```\n") || blockText.hasSuffix("```") {
                let suffixLen = blockText.hasSuffix("```\n") ? 4 : 3
                let dimRange = NSRange(location: range.location + range.length - suffixLen, length: suffixLen)
                if dimRange.location >= 0 {
                    attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: dimRange)
                }
            }
        }
    }

    // MARK: - Link

    mutating func visitLink(_ link: Link) {
        guard let range = nsRange(for: link) else {
            descendInto(link)
            return
        }

        attributed.addAttribute(.foregroundColor, value: style.linkColor, range: range)
        if let dest = link.destination, let url = URL(string: dest) {
            attributed.addAttribute(.link, value: url, range: range)
        }

        descendInto(link)
    }

    // MARK: - Block Quote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = nsRange(for: blockQuote) else {
            descendInto(blockQuote)
            return
        }

        attributed.addAttribute(.foregroundColor, value: style.blockQuoteColor, range: range)

        let indent = NSMutableParagraphStyle()
        indent.headIndent = 20
        indent.firstLineHeadIndent = 20
        indent.lineSpacing = style.lineSpacing
        attributed.addAttribute(.paragraphStyle, value: indent, range: range)

        descendInto(blockQuote)
    }

    // MARK: - Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        guard let range = nsRange(for: strikethrough) else {
            descendInto(strikethrough)
            return
        }

        attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        dimDelimiters(in: range, prefix: "~~", suffix: "~~")

        descendInto(strikethrough)
    }

    // MARK: - List Item

    mutating func visitListItem(_ listItem: ListItem) {
        guard let range = nsRange(for: listItem) else {
            descendInto(listItem)
            return
        }

        // Determine nesting level
        var depth = 0
        var parent = listItem.parent
        while parent != nil {
            if parent is UnorderedList || parent is OrderedList {
                depth += 1
            }
            parent = parent?.parent
        }

        let indent = NSMutableParagraphStyle()
        let indentAmount = CGFloat(depth) * 20.0
        indent.headIndent = indentAmount
        indent.firstLineHeadIndent = max(0, indentAmount - 20)
        indent.lineSpacing = style.lineSpacing

        // Tab stop for bullet alignment
        indent.tabStops = [NSTextTab(textAlignment: .left, location: indentAmount)]

        attributed.addAttribute(.paragraphStyle, value: indent, range: range)

        descendInto(listItem)
    }

    // MARK: - Image

    mutating func visitImage(_ image: Image) {
        guard let range = nsRange(for: image) else { return }

        if let source = image.source {
            imageReferences.append(ImageReference(range: range, source: source))
        }

        // Style the image syntax with link color
        attributed.addAttribute(.foregroundColor, value: style.linkColor, range: range)

        // Dim the syntax characters: ![ ]( )
        let text = attributed.string as NSString
        let imageText = text.substring(with: range)

        if imageText.hasPrefix("![") {
            let dimRange = NSRange(location: range.location, length: 2)
            if dimRange.location + dimRange.length <= attributed.length {
                attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: dimRange)
            }
        }

        if let bracketRange = imageText.range(of: "](") {
            let offset = imageText.distance(from: imageText.startIndex, to: bracketRange.lowerBound)
            let dimRange = NSRange(location: range.location + offset, length: 2)
            if dimRange.location + dimRange.length <= attributed.length {
                attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: dimRange)
            }
        }

        if imageText.hasSuffix(")") {
            let dimRange = NSRange(location: range.location + range.length - 1, length: 1)
            if dimRange.location + dimRange.length <= attributed.length {
                attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: dimRange)
            }
        }
    }

    // MARK: - Helpers

    private func applyFontTrait(_ trait: NSFontTraitMask, in range: NSRange) {
        attributed.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            let newFont = NSFontManager.shared.convert(font, toHaveTrait: trait)
            attributed.addAttribute(.font, value: newFont, range: subRange)
        }
    }

    private func dimDelimiters(in range: NSRange, prefix: String, suffix: String) {
        let prefixLen = prefix.utf16.count
        let suffixLen = suffix.utf16.count

        if prefixLen > 0 && range.length >= prefixLen {
            let prefixRange = NSRange(location: range.location, length: prefixLen)
            attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: prefixRange)
        }

        if suffixLen > 0 && range.length >= prefixLen + suffixLen {
            let suffixRange = NSRange(location: range.location + range.length - suffixLen, length: suffixLen)
            attributed.addAttribute(.foregroundColor, value: style.dimmedColor, range: suffixRange)
        }
    }
}
