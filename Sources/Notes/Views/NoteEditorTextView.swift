import AppKit

protocol NoteEditorImageDelegate: AnyObject {
    func noteEditor(_ editor: NoteEditorTextView, didDropImageFiles urls: [URL])
    func noteEditor(_ editor: NoteEditorTextView, didPasteImageData data: Data, type: NSBitmapImageRep.FileType)
}

class NoteEditorTextView: NSTextView {
    weak var imageDelegate: NoteEditorImageDelegate?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        usesFindBar = true
        textContainerInset = NSSize(width: 40, height: 30)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]

        if let tc = textContainer {
            tc.widthTracksTextView = true
            tc.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        font = .systemFont(ofSize: 15)
        textColor = .labelColor
        backgroundColor = .textBackgroundColor
        insertionPointColor = .labelColor

        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if imageURLs(from: sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if imageURLs(from: sender) != nil {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let urls = imageURLs(from: sender), !urls.isEmpty {
            // Position cursor at drop point
            let point = convert(sender.draggingLocation, from: nil)
            let charIndex = characterIndexForInsertion(at: point)
            setSelectedRange(NSRange(location: charIndex, length: 0))

            imageDelegate?.noteEditor(self, didDropImageFiles: urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func imageURLs(from draggingInfo: NSDraggingInfo) -> [URL]? {
        guard let urls = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingContentsConformToTypes: NSImage.imageTypes]
        ) as? [URL], !urls.isEmpty else { return nil }
        return urls
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check for image data (screenshots, copied images)
        if let imageData = pasteboard.data(forType: .png) {
            imageDelegate?.noteEditor(self, didPasteImageData: imageData, type: .png)
            return
        }
        if let imageData = pasteboard.data(forType: .tiff) {
            imageDelegate?.noteEditor(self, didPasteImageData: imageData, type: .tiff)
            return
        }

        // Check for image file URLs (from Finder)
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingContentsConformToTypes: NSImage.imageTypes]
        ) as? [URL], !urls.isEmpty {
            imageDelegate?.noteEditor(self, didDropImageFiles: urls)
            return
        }

        // Default text paste
        super.paste(sender)
    }
}
