import AppKit

protocol MainWindowControllerDelegate: AnyObject {
    func mainWindowDidRequestNewNote(_ controller: MainWindowController)
    func mainWindowDidRequestDelete(_ controller: MainWindowController)
}

class MainWindowController: NSWindowController, NSToolbarDelegate {
    let splitViewController = NSSplitViewController()
    let sidebarVC = SidebarViewController()
    let editorVC = EditorViewController()

    weak var mainDelegate: MainWindowControllerDelegate?

    private var noteStore: NoteStore!
    private var searchField: NSSearchField?

    init(noteStore: NoteStore) {
        self.noteStore = noteStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.setFrameAutosaveName("MainNotesWindow")
        window.minSize = NSSize(width: 500, height: 300)
        window.center()

        super.init(window: window)

        setupSplitView()
        setupToolbar()

        sidebarVC.sidebarDelegate = self
        editorVC.editorDelegate = self
        editorVC.noteStore = noteStore
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSplitView() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 350
        sidebarItem.canCollapse = true

        let editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = 300

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(editorItem)

        window?.contentViewController = splitViewController
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    func refreshSidebar(notes: [Note]) {
        sidebarVC.updateNotes(notes)
    }

    func selectFirstNote() {
        sidebarVC.selectNote(at: 0)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: .toggleSidebar)
            return item
        case .newNote:
            let item = NSToolbarItem(itemIdentifier: .newNote)
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New Note")
            item.label = "New Note"
            item.toolTip = "Create a new note"
            item.target = self
            item.action = #selector(newNoteAction)
            return item
        case .deleteNote:
            let item = NSToolbarItem(itemIdentifier: .deleteNote)
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Note")
            item.label = "Delete"
            item.toolTip = "Delete selected note"
            item.target = self
            item.action = #selector(deleteNoteAction)
            return item
        case .searchField:
            let item = NSSearchToolbarItem(itemIdentifier: .searchField)
            item.searchField.placeholderString = "Search Notes"
            item.searchField.target = self
            item.searchField.action = #selector(searchAction(_:))
            self.searchField = item.searchField
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .toggleSidebar,
            .newNote,
            .deleteNote,
            .flexibleSpace,
            .searchField,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }

    // MARK: - Actions

    @objc private func newNoteAction() {
        mainDelegate?.mainWindowDidRequestNewNote(self)
    }

    @objc private func deleteNoteAction() {
        mainDelegate?.mainWindowDidRequestDelete(self)
    }

    @objc private func searchAction(_ sender: NSSearchField) {
        let query = sender.stringValue.lowercased()
        if query.isEmpty {
            sidebarVC.updateNotes(noteStore.notes)
        } else {
            let filtered = noteStore.notes.filter {
                $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
            }
            sidebarVC.updateNotes(filtered)
        }
    }
}

// MARK: - Sidebar Delegate

extension MainWindowController: SidebarViewControllerDelegate {
    func sidebarDidSelectNote(_ sidebar: SidebarViewController, note: Note) {
        editorVC.displayNote(note)
    }

    func sidebarDidRequestDeleteNote(_ sidebar: SidebarViewController, note: Note) {
        noteStore.delete(note: note)
        sidebarVC.updateNotes(noteStore.notes)

        if editorVC.currentNote?.id == note.id {
            if let first = noteStore.notes.first {
                sidebarVC.selectNote(at: 0)
                editorVC.displayNote(first)
            } else {
                editorVC.clearEditor()
            }
        }
    }

    func sidebarDidRequestRenameNote(_ sidebar: SidebarViewController, note: Note) {
        let alert = NSAlert()
        alert.messageText = "Rename Note"
        alert.informativeText = "Enter a new name for this note."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = note.title
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let newTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty, newTitle != note.title else { return }

            self?.performRename(note: note, to: newTitle)
        }
    }

    func sidebarDidRequestRevealNote(_ sidebar: SidebarViewController, note: Note) {
        NSWorkspace.shared.activateFileViewerSelecting([note.fileURL])
    }

    private func performRename(note: Note, to newTitle: String) {
        var updatedNote = note
        let lines = note.body.components(separatedBy: "\n")
        var newLines = lines
        var replaced = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                newLines[index] = "# \(newTitle)"
                replaced = true
                break
            }
            if !trimmed.isEmpty {
                break
            }
        }

        if !replaced {
            newLines.insert("# \(newTitle)", at: 0)
        }

        updatedNote.body = newLines.joined(separator: "\n")
        updatedNote.title = newTitle
        updatedNote.modifiedDate = Date()

        noteStore.save(note: updatedNote)
        sidebarVC.updateNotes(noteStore.notes)

        if editorVC.currentNote?.id == note.id {
            editorVC.displayNote(updatedNote)
        }
    }
}

// MARK: - Editor Delegate

extension MainWindowController: EditorViewControllerDelegate {
    func editorDidChangeNote(_ editor: EditorViewController, note: Note) {
        noteStore.save(note: note)
        // Refresh sidebar to update title/preview
        sidebarVC.updateNotes(noteStore.notes)
    }
}

// MARK: - Toolbar Identifiers

extension NSToolbarItem.Identifier {
    static let newNote = NSToolbarItem.Identifier("NewNote")
    static let deleteNote = NSToolbarItem.Identifier("DeleteNote")
    static let searchField = NSToolbarItem.Identifier("SearchField")
}
