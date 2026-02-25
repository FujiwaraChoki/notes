import AppKit
import UniformTypeIdentifiers

protocol EditorViewControllerDelegate: AnyObject {
    func editorDidChangeNote(_ editor: EditorViewController, note: Note)
}

class EditorViewController: NSViewController, NSTextViewDelegate {
    private var scrollView: NSScrollView!
    private var textView: NoteEditorTextView!
    private let formatter = MarkdownFormatter()
    private let debouncer = Debouncer(delay: 0.5)
    private var isFormatting = false
    private(set) var currentNote: Note?

    // Image support
    weak var noteStore: NoteStore?
    private var imageCache: [String: NSImage] = [:]

    weak var editorDelegate: EditorViewControllerDelegate?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        textView = NoteEditorTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.imageDelegate = self

        scrollView.documentView = textView
        container.addSubview(scrollView)

        // AI buttons container (bottom-right)
        let aiStack = NSStackView()
        aiStack.orientation = .horizontal
        aiStack.spacing = 8
        aiStack.translatesAutoresizingMaskIntoConstraints = false

        let chatGPTButton = makeAIButton(iconPath: AIIcons.chatGPTPath, tooltip: "Ask ChatGPT")
        chatGPTButton.target = self
        chatGPTButton.action = #selector(openInChatGPT)

        let claudeButton = makeAIButton(iconPath: AIIcons.claudePath, tooltip: "Ask Claude")
        claudeButton.target = self
        claudeButton.action = #selector(openInClaude)

        aiStack.addArrangedSubview(chatGPTButton)
        aiStack.addArrangedSubview(claudeButton)
        container.addSubview(aiStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            aiStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            aiStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        self.view = container
    }

    func displayNote(_ note: Note) {
        imageCache.removeAll()
        currentNote = note

        isFormatting = true
        let formatted = formatter.format(note.body)
        let display = insertImageAttachments(into: formatted)
        textView.textStorage?.setAttributedString(display)
        isFormatting = false
    }

    func clearEditor() {
        currentNote = nil
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isFormatting, var note = currentNote else { return }

        // Strip attachment characters to recover raw markdown
        let rawText = extractRawMarkdown()
        note.body = rawText
        note.title = Note.extractTitle(from: rawText)
        note.modifiedDate = Date()
        currentNote = note

        reformatText()

        debouncer.call { [weak self] in
            guard let self = self, let note = self.currentNote else { return }
            self.editorDelegate?.editorDidChangeNote(self, note: note)
        }
    }

    /// Strip `\n\u{FFFC}` (newline + object replacement char) inserted for image previews.
    private func extractRawMarkdown() -> String {
        return textView.string
            .replacingOccurrences(of: "\n\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    private func reformatText() {
        guard let textStorage = textView.textStorage,
              let note = currentNote else { return }

        isFormatting = true

        // Convert display cursor → source cursor
        let displayCursor = textView.selectedRange().location
        let sourceCursor = displayToSource(displayCursor)

        // Format raw markdown, then insert image attachments
        let formatted = formatter.format(note.body)
        let display = insertImageAttachments(into: formatted)

        textStorage.beginEditing()
        textStorage.setAttributedString(display)
        textStorage.endEditing()

        // Convert source cursor → new display cursor
        let newDisplayCursor = sourceToDisplay(sourceCursor, in: textView.string)
        let safePos = min(newDisplayCursor, textView.string.utf16.count)
        textView.setSelectedRange(NSRange(location: safePos, length: 0))

        isFormatting = false
    }

    // MARK: - Image Attachments

    /// Insert `\n` + NSTextAttachment after each image-syntax line (processed in reverse).
    private func insertImageAttachments(into source: NSMutableAttributedString) -> NSMutableAttributedString {
        let refs = formatter.lastImageReferences
        let result = NSMutableAttributedString(attributedString: source)

        // Process in reverse so earlier offsets stay valid
        for ref in refs.reversed() {
            guard let image = loadImage(at: ref.source) else { continue }

            let maxWidth = max((textView?.textContainer?.containerSize.width ?? 600) - 80, 200)
            let scale = image.size.width > maxWidth ? maxWidth / image.size.width : 1.0

            let sized = NSImage(size: NSSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
            sized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: sized.size))
            sized.unlockFocus()

            let attachment = NSTextAttachment()
            let cell = NSTextAttachmentCell(imageCell: sized)
            attachment.attachmentCell = cell

            let attachStr = NSAttributedString(attachment: attachment)
            let newline = NSAttributedString(string: "\n")

            // Insert right after the image-syntax range
            let insertPos = min(ref.range.location + ref.range.length, result.length)
            result.insert(attachStr, at: insertPos)
            result.insert(newline, at: insertPos)
        }

        return result
    }

    // MARK: - Cursor Mapping (display ↔ source)

    /// Walk the current display string; skip every `\n\u{FFFC}` pair.
    private func displayToSource(_ displayPos: Int) -> Int {
        let s = textView.string
        let u = s.utf16
        var src = 0
        var i = u.startIndex
        var disp = 0

        while disp < displayPos, i < u.endIndex {
            // Check for \n followed by \u{FFFC}
            let next = u.index(after: i)
            if u[i] == 0x000A, next < u.endIndex, u[next] == 0xFFFC {
                // Skip both
                i = u.index(after: next)
                disp += 2
                continue
            }
            if u[i] == 0xFFFC {
                i = u.index(after: i)
                disp += 1
                continue
            }
            src += 1
            disp += 1
            i = u.index(after: i)
        }
        return src
    }

    /// Given a source offset, find the matching display offset in a new display string.
    private func sourceToDisplay(_ sourcePos: Int, in displayString: String) -> Int {
        let u = displayString.utf16
        var src = 0
        var disp = 0
        var i = u.startIndex

        while src < sourcePos, i < u.endIndex {
            let next = u.index(after: i)
            if u[i] == 0x000A, next < u.endIndex, u[next] == 0xFFFC {
                i = u.index(after: next)
                disp += 2
                continue
            }
            if u[i] == 0xFFFC {
                i = u.index(after: i)
                disp += 1
                continue
            }
            src += 1
            disp += 1
            i = u.index(after: i)
        }
        return disp
    }

    private func loadImage(at relativePath: String) -> NSImage? {
        if relativePath.hasPrefix("http://") || relativePath.hasPrefix("https://") {
            return nil
        }
        if let cached = imageCache[relativePath] {
            return cached
        }
        guard let note = currentNote else { return nil }
        let baseURL = note.fileURL.deletingLastPathComponent()
        let imageURL = baseURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: imageURL.path),
              let image = NSImage(contentsOf: imageURL) else { return nil }
        imageCache[relativePath] = image
        return image
    }

    // MARK: - Image Insertion

    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose images to insert"

        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.insertImageFromFile(url)
            }
        }
    }

    private func insertImageFromFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let store = noteStore,
              let relativePath = store.saveImageToAssets(data: data, suggestedName: url.lastPathComponent) else { return }
        let altText = url.deletingPathExtension().lastPathComponent
        insertImageMarkdown(relativePath: relativePath, altText: altText)
    }

    private func insertImageData(_ data: Data, suggestedName: String) {
        guard let store = noteStore,
              let relativePath = store.saveImageToAssets(data: data, suggestedName: suggestedName) else { return }
        insertImageMarkdown(relativePath: relativePath, altText: "")
    }

    private func insertImageMarkdown(relativePath: String, altText: String) {
        let markdown = "![\(altText)](\(relativePath))"
        let selectedRange = textView.selectedRange()

        // Ensure image is on its own line
        var prefix = ""
        if selectedRange.location > 0 {
            let text = textView.string as NSString
            let prevChar = text.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
            if prevChar != "\n" {
                prefix = "\n"
            }
        }

        var suffix = "\n"
        let text = textView.string as NSString
        if selectedRange.location < text.length {
            let nextChar = text.substring(with: NSRange(location: selectedRange.location, length: 1))
            if nextChar == "\n" {
                suffix = ""
            }
        }

        textView.insertText(prefix + markdown + suffix, replacementRange: selectedRange)
    }

    // MARK: - Format Actions

    func toggleBold() {
        wrapSelection(prefix: "**", suffix: "**")
    }

    func toggleItalic() {
        wrapSelection(prefix: "*", suffix: "*")
    }

    func applyHeading(level: Int) {
        let prefix = String(repeating: "#", count: level) + " "
        guard let textStorage = textView.textStorage else { return }
        let selectedRange = textView.selectedRange()
        let text = textStorage.string as NSString

        // Find the start of the current line
        let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let lineText = text.substring(with: lineRange)

        // Remove existing heading markers
        var cleanLine = lineText
        while cleanLine.hasPrefix("#") {
            cleanLine = String(cleanLine.dropFirst())
        }
        if cleanLine.hasPrefix(" ") {
            cleanLine = String(cleanLine.dropFirst())
        }

        let newLine = prefix + cleanLine
        textView.insertText(newLine, replacementRange: lineRange)
    }

    // MARK: - AI Actions

    private func makeAIButton(iconPath: String, tooltip: String) -> HoverButton {
        let button = HoverButton(iconPath: iconPath, tooltip: tooltip)
        return button
    }

    private func buildPrompt() -> String {
        guard let note = currentNote else { return "" }
        return "Please read the following note and share your thoughts, feedback, and any suggestions for improvement:\n\n\(note.body)"
    }

    @objc private func openInChatGPT() {
        let prompt = buildPrompt()
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://chatgpt.com/?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openInClaude() {
        let prompt = buildPrompt()
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://claude.ai/new?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func wrapSelection(prefix: String, suffix: String) {
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else { return }

        let text = textView.string as NSString
        let selectedText = text.substring(with: selectedRange)

        // Check if already wrapped
        let prefixLen = prefix.utf16.count
        let suffixLen = suffix.utf16.count

        if selectedRange.location >= prefixLen
            && selectedRange.location + selectedRange.length + suffixLen <= text.length {
            let beforeRange = NSRange(location: selectedRange.location - prefixLen, length: prefixLen)
            let afterRange = NSRange(location: selectedRange.location + selectedRange.length, length: suffixLen)
            let before = text.substring(with: beforeRange)
            let after = text.substring(with: afterRange)

            if before == prefix && after == suffix {
                // Unwrap
                let fullRange = NSRange(
                    location: selectedRange.location - prefixLen,
                    length: selectedRange.length + prefixLen + suffixLen
                )
                textView.insertText(selectedText, replacementRange: fullRange)
                return
            }
        }

        // Wrap
        let wrapped = prefix + selectedText + suffix
        textView.insertText(wrapped, replacementRange: selectedRange)
    }
}

// MARK: - NoteEditorImageDelegate

extension EditorViewController: NoteEditorImageDelegate {
    func noteEditor(_ editor: NoteEditorTextView, didDropImageFiles urls: [URL]) {
        for url in urls {
            insertImageFromFile(url)
        }
    }

    func noteEditor(_ editor: NoteEditorTextView, didPasteImageData data: Data, type: NSBitmapImageRep.FileType) {
        let imageData: Data
        let ext: String

        // Convert TIFF to PNG for better compatibility/size
        if type == .tiff, let rep = NSBitmapImageRep(data: data),
           let pngData = rep.representation(using: .png, properties: [:]) {
            imageData = pngData
            ext = "png"
        } else {
            imageData = data
            ext = type == .png ? "png" : "tiff"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "image_\(timestamp).\(ext)"

        insertImageData(imageData, suggestedName: filename)
    }
}

// MARK: - HoverButton

class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let iconLayer = CALayer()
    private let iconPathData: String
    private var isHovered = false

    init(iconPath: String, tooltip: String) {
        self.iconPathData = iconPath
        super.init(frame: .zero)

        bezelStyle = .texturedRounded
        isBordered = false
        title = ""
        toolTip = tooltip
        translatesAutoresizingMaskIntoConstraints = false
        imagePosition = .noImage

        let size: CGFloat = 28
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])

        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Icon sublayer
        let iconSize: CGFloat = 16
        iconLayer.frame = CGRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        iconLayer.opacity = 0.4
        layer?.addSublayer(iconLayer)
        renderIcon()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func renderIcon() {
        let iconSize: CGFloat = 16
        let imgSize = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: imgSize, flipped: false) { rect in
            let bezier = NSBezierPath()
            bezier.parseSVGPath(self.iconPathData, in: rect, viewBox: NSRect(x: 0, y: 0, width: 16, height: 16))
            NSColor.labelColor.setFill()
            bezier.fill()
            return true
        }
        iconLayer.contents = image
        iconLayer.contentsGravity = .resizeAspect
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isHovered {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iconLayer.opacity = 1.0
        }
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            iconLayer.opacity = 0.4
        }
        NSCursor.arrow.set()
    }
}

// MARK: - AI Icon SVG Paths

enum AIIcons {
    // OpenAI / ChatGPT logo (Bootstrap Icons)
    static let chatGPTPath = "M14.949 6.547a3.94 3.94 0 0 0-.348-3.273 4.11 4.11 0 0 0-4.4-1.934 4.1 4.1 0 0 0-1.778-.613 4.15 4.15 0 0 0-2.118-.114 4.1 4.1 0 0 0-1.891.948 4.04 4.04 0 0 0-1.158 1.753 4.1 4.1 0 0 0-1.563.679 4 4 0 0 0-1.14 1.253 3.99 3.99 0 0 0 .502 4.731 3.94 3.94 0 0 0 .346 3.274 4.11 4.11 0 0 0 4.402 1.933c.382.425.852.764 1.377.995.526.231 1.095.35 1.67.346 1.78.002 3.358-1.132 3.901-2.804a4.1 4.1 0 0 0 1.563-.68 4 4 0 0 0 1.14-1.253 3.99 3.99 0 0 0-.506-4.716m-6.097 8.406a3.05 3.05 0 0 1-1.945-.694l.096-.054 3.23-1.838a.53.53 0 0 0 .265-.455v-4.49l1.366.778q.02.011.025.035v3.722c-.003 1.653-1.361 2.992-3.037 2.996m-6.53-2.75a2.95 2.95 0 0 1-.36-2.01l.095.057L5.29 12.09a.53.53 0 0 0 .527 0l3.949-2.246v1.555a.05.05 0 0 1-.022.041L6.473 13.3c-1.454.826-3.311.335-4.15-1.098m-.85-6.94A3.02 3.02 0 0 1 3.07 3.949v3.785a.51.51 0 0 0 .262.451l3.93 2.237-1.366.779a.05.05 0 0 1-.048 0L2.585 9.342a2.98 2.98 0 0 1-1.113-4.094zm11.216 2.571L8.747 5.576l1.362-.776a.05.05 0 0 1 .048 0l3.265 1.86a3 3 0 0 1 1.173 1.207 2.96 2.96 0 0 1-.27 3.2 3.05 3.05 0 0 1-1.36.997V8.279a.52.52 0 0 0-.276-.445m1.36-2.015-.097-.057-3.226-1.855a.53.53 0 0 0-.53 0L6.249 6.153V4.598a.04.04 0 0 1 .019-.04L9.533 2.7a3.07 3.07 0 0 1 3.257.139c.474.325.843.778 1.066 1.303.223.526.289 1.103.191 1.664zM5.503 8.575 4.139 7.8a.05.05 0 0 1-.026-.037V4.049c0-.57.166-1.127.476-1.607s.752-.864 1.275-1.105a3.08 3.08 0 0 1 3.234.41l-.096.054-3.23 1.838a.53.53 0 0 0-.265.455zm.742-1.577 1.758-1 1.762 1v2l-1.755 1-1.762-1z"

    // Claude / Anthropic logo (Bootstrap Icons)
    static let claudePath = "m3.127 10.604 3.135-1.76.053-.153-.053-.085H6.11l-.525-.032-1.791-.048-1.554-.065-1.505-.08-.38-.081L0 7.832l.036-.234.32-.214.455.04 1.009.069 1.513.105 1.097.064 1.626.17h.259l.036-.105-.089-.065-.068-.064-1.566-1.062-1.695-1.121-.887-.646-.48-.327-.243-.306-.104-.67.435-.48.585.04.15.04.593.456 1.267.981 1.654 1.218.242.202.097-.068.012-.049-.109-.181-.9-1.626-.96-1.655-.428-.686-.113-.411a2 2 0 0 1-.068-.484l.496-.674L4.446 0l.662.089.279.242.411.94.666 1.48 1.033 2.014.302.597.162.553.06.17h.105v-.097l.085-1.134.157-1.392.154-1.792.052-.504.25-.605.497-.327.387.186.319.456-.045.294-.19 1.23-.37 1.93-.243 1.29h.142l.161-.16.654-.868 1.097-1.372.484-.545.565-.601.363-.287h.686l.505.751-.226.775-.707.895-.585.759-.839 1.13-.524.904.048.072.125-.012 1.897-.403 1.024-.186 1.223-.21.553.258.06.263-.218.536-1.307.323-1.533.307-2.284.54-.028.02.032.04 1.029.098.44.024h1.077l2.005.15.525.346.315.424-.053.323-.807.411-3.631-.863-.872-.218h-.12v.073l.726.71 1.331 1.202 1.667 1.55.084.383-.214.302-.226-.032-1.464-1.101-.565-.497-1.28-1.077h-.084v.113l.295.432 1.557 2.34.08.718-.112.234-.404.141-.444-.08-.911-1.28-.94-1.44-.759-1.291-.093.053-.448 4.821-.21.246-.484.186-.403-.307-.214-.496.214-.98.258-1.28.21-1.016.19-1.263.112-.42-.008-.028-.092.012-.953 1.307-1.448 1.957-1.146 1.227-.274.109-.477-.247.045-.44.266-.39 1.586-2.018.956-1.25.617-.723-.004-.105h-.036l-4.212 2.736-.75.096-.324-.302.04-.496.154-.162 1.267-.871z"
}

// MARK: - NSBezierPath SVG Path Parser

extension NSBezierPath {
    func parseSVGPath(_ pathData: String, in targetRect: NSRect, viewBox: NSRect) {
        let scaleX = targetRect.width / viewBox.width
        let scaleY = targetRect.height / viewBox.height

        func tx(_ x: CGFloat) -> CGFloat { targetRect.origin.x + x * scaleX }
        func ty(_ y: CGFloat) -> CGFloat { targetRect.origin.y + targetRect.height - y * scaleY }

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var lastControlX: CGFloat = 0
        var lastControlY: CGFloat = 0

        let scanner = Scanner(string: pathData)
        scanner.charactersToBeSkipped = nil

        func skipWhitespaceAndCommas() {
            _ = scanner.scanCharacters(from: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        }

        func scanNumber() -> CGFloat? {
            skipWhitespaceAndCommas()
            guard let result = scanner.scanDouble() else { return nil }
            return CGFloat(result)
        }

        func scanCommand() -> Character? {
            skipWhitespaceAndCommas()
            let pos = scanner.currentIndex
            if pos < pathData.endIndex {
                let ch = pathData[pos]
                if "MmLlHhVvCcSsQqTtAaZz".contains(ch) {
                    scanner.currentIndex = pathData.index(after: pos)
                    return ch
                }
            }
            return nil
        }

        while !scanner.isAtEnd {
            if let cmd = scanCommand() {

                switch cmd {
                case "M":
                    guard let x = scanNumber(), let y = scanNumber() else { break }
                    currentX = x; currentY = y
                    startX = x; startY = y
                    move(to: NSPoint(x: tx(x), y: ty(y)))
                    // Subsequent coordinate pairs are implicit lineTo
                    while let x = scanNumber(), let y = scanNumber() {
                        currentX = x; currentY = y
                        line(to: NSPoint(x: tx(x), y: ty(y)))
                    }
                case "m":
                    guard let dx = scanNumber(), let dy = scanNumber() else { break }
                    currentX += dx; currentY += dy
                    startX = currentX; startY = currentY
                    move(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    while let dx = scanNumber(), let dy = scanNumber() {
                        currentX += dx; currentY += dy
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "L":
                    while let x = scanNumber(), let y = scanNumber() {
                        currentX = x; currentY = y
                        line(to: NSPoint(x: tx(x), y: ty(y)))
                    }
                case "l":
                    while let dx = scanNumber(), let dy = scanNumber() {
                        currentX += dx; currentY += dy
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "H":
                    while let x = scanNumber() {
                        currentX = x
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "h":
                    while let dx = scanNumber() {
                        currentX += dx
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "V":
                    while let y = scanNumber() {
                        currentY = y
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "v":
                    while let dy = scanNumber() {
                        currentY += dy
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "C":
                    while let x1 = scanNumber(), let y1 = scanNumber(),
                          let x2 = scanNumber(), let y2 = scanNumber(),
                          let x = scanNumber(), let y = scanNumber() {
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                              controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                        lastControlX = x2; lastControlY = y2
                        currentX = x; currentY = y
                    }
                case "c":
                    while let dx1 = scanNumber(), let dy1 = scanNumber(),
                          let dx2 = scanNumber(), let dy2 = scanNumber(),
                          let dx = scanNumber(), let dy = scanNumber() {
                        let x1 = currentX + dx1, y1 = currentY + dy1
                        let x2 = currentX + dx2, y2 = currentY + dy2
                        let x = currentX + dx, y = currentY + dy
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                              controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                        lastControlX = x2; lastControlY = y2
                        currentX = x; currentY = y
                    }
                case "S":
                    while let x2 = scanNumber(), let y2 = scanNumber(),
                          let x = scanNumber(), let y = scanNumber() {
                        let x1 = 2 * currentX - lastControlX
                        let y1 = 2 * currentY - lastControlY
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                              controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                        lastControlX = x2; lastControlY = y2
                        currentX = x; currentY = y
                    }
                case "s":
                    while let dx2 = scanNumber(), let dy2 = scanNumber(),
                          let dx = scanNumber(), let dy = scanNumber() {
                        let x1 = 2 * currentX - lastControlX
                        let y1 = 2 * currentY - lastControlY
                        let x2 = currentX + dx2, y2 = currentY + dy2
                        let x = currentX + dx, y = currentY + dy
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(x1), y: ty(y1)),
                              controlPoint2: NSPoint(x: tx(x2), y: ty(y2)))
                        lastControlX = x2; lastControlY = y2
                        currentX = x; currentY = y
                    }
                case "Q":
                    while let cx = scanNumber(), let cy = scanNumber(),
                          let x = scanNumber(), let y = scanNumber() {
                        // Convert quadratic to cubic
                        let cp1x = currentX + 2.0/3.0 * (cx - currentX)
                        let cp1y = currentY + 2.0/3.0 * (cy - currentY)
                        let cp2x = x + 2.0/3.0 * (cx - x)
                        let cp2y = y + 2.0/3.0 * (cy - y)
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(cp1x), y: ty(cp1y)),
                              controlPoint2: NSPoint(x: tx(cp2x), y: ty(cp2y)))
                        lastControlX = cx; lastControlY = cy
                        currentX = x; currentY = y
                    }
                case "q":
                    while let dcx = scanNumber(), let dcy = scanNumber(),
                          let dx = scanNumber(), let dy = scanNumber() {
                        let cx = currentX + dcx, cy = currentY + dcy
                        let x = currentX + dx, y = currentY + dy
                        let cp1x = currentX + 2.0/3.0 * (cx - currentX)
                        let cp1y = currentY + 2.0/3.0 * (cy - currentY)
                        let cp2x = x + 2.0/3.0 * (cx - x)
                        let cp2y = y + 2.0/3.0 * (cy - y)
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(cp1x), y: ty(cp1y)),
                              controlPoint2: NSPoint(x: tx(cp2x), y: ty(cp2y)))
                        lastControlX = cx; lastControlY = cy
                        currentX = x; currentY = y
                    }
                case "T":
                    while let x = scanNumber(), let y = scanNumber() {
                        let cx = 2 * currentX - lastControlX
                        let cy = 2 * currentY - lastControlY
                        let cp1x = currentX + 2.0/3.0 * (cx - currentX)
                        let cp1y = currentY + 2.0/3.0 * (cy - currentY)
                        let cp2x = x + 2.0/3.0 * (cx - x)
                        let cp2y = y + 2.0/3.0 * (cy - y)
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(cp1x), y: ty(cp1y)),
                              controlPoint2: NSPoint(x: tx(cp2x), y: ty(cp2y)))
                        lastControlX = cx; lastControlY = cy
                        currentX = x; currentY = y
                    }
                case "t":
                    while let dx = scanNumber(), let dy = scanNumber() {
                        let cx = 2 * currentX - lastControlX
                        let cy = 2 * currentY - lastControlY
                        let x = currentX + dx, y = currentY + dy
                        let cp1x = currentX + 2.0/3.0 * (cx - currentX)
                        let cp1y = currentY + 2.0/3.0 * (cy - currentY)
                        let cp2x = x + 2.0/3.0 * (cx - x)
                        let cp2y = y + 2.0/3.0 * (cy - y)
                        curve(to: NSPoint(x: tx(x), y: ty(y)),
                              controlPoint1: NSPoint(x: tx(cp1x), y: ty(cp1y)),
                              controlPoint2: NSPoint(x: tx(cp2x), y: ty(cp2y)))
                        lastControlX = cx; lastControlY = cy
                        currentX = x; currentY = y
                    }
                case "A", "a":
                    // Simplified arc: just lineTo endpoint
                    let relative = cmd == "a"
                    while let _ = scanNumber(), let _ = scanNumber(),
                          let _ = scanNumber(), let _ = scanNumber(),
                          let _ = scanNumber(), let ex = scanNumber(), let ey = scanNumber() {
                        if relative {
                            currentX += ex; currentY += ey
                        } else {
                            currentX = ex; currentY = ey
                        }
                        line(to: NSPoint(x: tx(currentX), y: ty(currentY)))
                    }
                case "Z", "z":
                    close()
                    currentX = startX; currentY = startY
                default:
                    break
                }
            } else {
                // Might be implicit repeated command (numbers without a new command letter)
                // Try to consume as repeats of the last command
                if let _ = scanNumber() {
                    // Put it back and break to avoid infinite loop
                    break
                }
                // Skip unknown character
                if scanner.currentIndex < pathData.endIndex {
                    scanner.currentIndex = pathData.index(after: scanner.currentIndex)
                }
            }
        }
    }
}
