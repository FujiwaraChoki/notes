import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelectNote(_ sidebar: SidebarViewController, note: Note)
    func sidebarDidRequestDeleteNote(_ sidebar: SidebarViewController, note: Note)
    func sidebarDidRequestRenameNote(_ sidebar: SidebarViewController, note: Note)
    func sidebarDidRequestRevealNote(_ sidebar: SidebarViewController, note: Note)
}

class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var notes: [Note] = []

    weak var sidebarDelegate: SidebarViewControllerDelegate?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        tableView = NSTableView()
        tableView.style = .sourceList
        tableView.headerView = nil
        tableView.rowHeight = 60
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteColumn"))
        column.title = ""
        column.isEditable = false
        tableView.addTableColumn(column)

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
    }

    func updateNotes(_ newNotes: [Note]) {
        let previouslySelectedId = selectedNote?.id
        notes = newNotes
        tableView.reloadData()

        // Restore selection
        if let previousId = previouslySelectedId,
           let index = notes.firstIndex(where: { $0.id == previousId }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    var selectedNote: Note? {
        let row = tableView.selectedRow
        guard row >= 0, row < notes.count else { return nil }
        return notes[row]
    }

    func selectNote(at index: Int) {
        guard index >= 0, index < notes.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return notes.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < notes.count else { return nil }
        let note = notes[row]

        let identifier = NSUserInterfaceItemIdentifier("NoteCell")
        let cellView: NoteCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NoteCellView {
            cellView = existing
        } else {
            cellView = NoteCellView()
            cellView.identifier = identifier
        }

        cellView.configure(with: note)
        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let note = selectedNote else { return }
        sidebarDelegate?.sidebarDidSelectNote(self, note: note)
    }
}

// MARK: - Context Menu

extension SidebarViewController {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0, clickedRow < notes.count else { return }

        let renameItem = NSMenuItem(title: "Rename...", action: #selector(contextRename(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.tag = clickedRow
        menu.addItem(renameItem)

        let revealItem = NSMenuItem(title: "Show in Finder", action: #selector(contextReveal(_:)), keyEquivalent: "")
        revealItem.target = self
        revealItem.tag = clickedRow
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.tag = clickedRow
        menu.addItem(deleteItem)
    }

    @objc private func contextRename(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < notes.count else { return }
        sidebarDelegate?.sidebarDidRequestRenameNote(self, note: notes[row])
    }

    @objc private func contextReveal(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < notes.count else { return }
        sidebarDelegate?.sidebarDidRequestRevealNote(self, note: notes[row])
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        let row = sender.tag
        guard row >= 0, row < notes.count else { return }
        sidebarDelegate?.sidebarDidRequestDeleteNote(self, note: notes[row])
    }
}

// MARK: - Cell View

private class NoteCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .secondaryLabelColor

        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = .tertiaryLabelColor
        snippetLabel.lineBreakMode = .byTruncatingTail

        let dateSnippetStack = NSStackView(views: [dateLabel, snippetLabel])
        dateSnippetStack.orientation = .horizontal
        dateSnippetStack.spacing = 6
        dateSnippetStack.alignment = .firstBaseline

        let stack = NSStackView(views: [titleLabel, dateSnippetStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        // Allow snippet to compress
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    func configure(with note: Note) {
        titleLabel.stringValue = note.title
        dateLabel.stringValue = formatDate(note.modifiedDate)
        snippetLabel.stringValue = note.previewSnippet
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}
