import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var noteStore: NoteStore!
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        noteStore = NoteStore()
        noteStore.delegate = self

        windowController = MainWindowController(noteStore: noteStore)
        windowController.mainDelegate = self
        windowController.refreshSidebar(notes: noteStore.notes)

        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)

        // Select first note if available
        if !noteStore.notes.isEmpty {
            windowController.selectFirstNote()
        }

        setupMenuBar()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Notes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Note", action: #selector(newNoteMenuAction), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Save", action: #selector(saveMenuAction), keyEquivalent: "s")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        let findItem = editMenu.addItem(withTitle: "Find...", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)

        let findNextItem = editMenu.addItem(withTitle: "Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g")
        findNextItem.tag = Int(NSFindPanelAction.next.rawValue)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Format menu
        let formatMenu = NSMenu(title: "Format")
        let boldItem = NSMenuItem(title: "Bold", action: #selector(boldMenuAction), keyEquivalent: "b")
        boldItem.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(boldItem)
        formatMenu.addItem(withTitle: "Italic", action: #selector(italicMenuAction), keyEquivalent: "i")
        formatMenu.addItem(.separator())

        let h1Item = NSMenuItem(title: "Heading 1", action: #selector(heading1Action), keyEquivalent: "1")
        h1Item.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(h1Item)

        let h2Item = NSMenuItem(title: "Heading 2", action: #selector(heading2Action), keyEquivalent: "2")
        h2Item.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(h2Item)

        let h3Item = NSMenuItem(title: "Heading 3", action: #selector(heading3Action), keyEquivalent: "3")
        h3Item.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(h3Item)

        formatMenu.addItem(.separator())
        let insertImageItem = NSMenuItem(title: "Insert Image...", action: #selector(insertImageMenuAction), keyEquivalent: "i")
        insertImageItem.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(insertImageItem)

        let formatMenuItem = NSMenuItem()
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let toggleSidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebarAction), keyEquivalent: "b")
        viewMenu.addItem(toggleSidebarItem)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func newNoteMenuAction() {
        createNewNote()
    }

    @objc private func saveMenuAction() {
        if let note = windowController.editorVC.currentNote {
            noteStore.save(note: note)
        }
    }

    @objc private func boldMenuAction() {
        windowController.editorVC.toggleBold()
    }

    @objc private func italicMenuAction() {
        windowController.editorVC.toggleItalic()
    }

    @objc private func heading1Action() {
        windowController.editorVC.applyHeading(level: 1)
    }

    @objc private func heading2Action() {
        windowController.editorVC.applyHeading(level: 2)
    }

    @objc private func heading3Action() {
        windowController.editorVC.applyHeading(level: 3)
    }

    @objc private func insertImageMenuAction() {
        windowController.editorVC.insertImage()
    }

    @objc private func toggleSidebarAction() {
        windowController.splitViewController.toggleSidebar(nil)
    }

    // MARK: - Helpers

    private func createNewNote() {
        let note = noteStore.createNote()
        windowController.refreshSidebar(notes: noteStore.notes)
        windowController.selectFirstNote()
        windowController.editorVC.displayNote(note)
        windowController.window?.makeFirstResponder(nil) // Focus editor
    }
}

// MARK: - NoteStoreDelegate

extension AppDelegate: NoteStoreDelegate {
    func noteStoreDidUpdate(_ store: NoteStore) {
        windowController.refreshSidebar(notes: store.notes)
    }
}

// MARK: - MainWindowControllerDelegate

extension AppDelegate: MainWindowControllerDelegate {
    func mainWindowDidRequestNewNote(_ controller: MainWindowController) {
        createNewNote()
    }

    func mainWindowDidRequestDelete(_ controller: MainWindowController) {
        guard let note = controller.editorVC.currentNote else { return }
        noteStore.delete(note: note)
        controller.refreshSidebar(notes: noteStore.notes)
        if let first = noteStore.notes.first {
            controller.selectFirstNote()
            controller.editorVC.displayNote(first)
        }
    }
}
