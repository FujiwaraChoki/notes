# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A native macOS notes application built in Swift using AppKit. It provides a markdown editor with syntax highlighting, file-system-backed persistence, and AI integration (ChatGPT/Claude web links).

- **Language:** Swift (language mode v5)
- **Build System:** Swift Package Manager (tools version 6.2)
- **Target:** macOS 14+
- **Key Dependency:** [swift-markdown](https://github.com/swiftlang/swift-markdown) v0.7.3 for AST-based markdown parsing

## Build & Run Commands

```bash
swift build              # Debug build
swift build -c release   # Release build
swift run Notes          # Build and run the app
```

No test targets are configured.

## Architecture

MVC pattern with delegation-based communication between components.

### Data Flow

```
EditorViewController (text change)
  → Debouncer (0.5s delay)
    → NoteStore (write .md file to ~/Documents/Notes)
      → DispatchSourceFileSystemObject (detects file changes)
        → NoteStore reloads → delegates update UI
```

### Key Layers

- **App/** — `AppDelegate` (lifecycle, menus) and `MainWindowController` (split view, toolbar, search, delegates between sidebar and editor)
- **Models/** — `Note` (immutable value type: UUID, file URL, title/body extraction from markdown) and `NoteStore` (file I/O, directory watching with `DispatchSource`, save/load/delete)
- **Views/** — `SidebarViewController` (note list table), `EditorViewController` (editor + AI buttons), `NoteEditorTextView` (custom `NSTextView` subclass)
- **Markdown/** — `MarkdownFormatter` uses swift-markdown's `MarkupWalker` to walk the AST and apply `NSAttributedString` styling. Handles UTF-8 → UTF-16 offset conversion for correct range mapping.
- **Utilities/** — `Debouncer` for throttling editor saves

### Important Patterns

- Controllers communicate via weak delegate protocols to avoid retain cycles
- `NoteStore` uses an `isSaving` flag to prevent file-watcher re-entry during writes
- Notes are plain `.md` files stored in `~/Documents/Notes` (configurable via `UserDefaults`)
- Deletion uses `NSFileManager.trashItem` (soft delete) with fallback to `removeItem`
- AI buttons open `chatgpt.com/?q=` or `claude.ai/new?q=` with URL-encoded note content
