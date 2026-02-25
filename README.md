# Notes

A native macOS notes app built with Swift and AppKit. Markdown editor with syntax highlighting, file-system-backed persistence, and AI integration.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Markdown editing with real-time syntax highlighting (powered by [swift-markdown](https://github.com/swiftlang/swift-markdown) AST)
- File-system backed storage — notes are plain `.md` files in `~/Documents/Notes`
- Sidebar with search and note management
- Auto-save with debounced writes
- Directory watching for external file changes
- AI integration — send note content to ChatGPT or Claude with one click

## Requirements

- macOS 14+ (Liquid Glass only supported in 26.0+)
- Swift 5 / Swift Package Manager (tools version 6.2)

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build
swift run Notes          # Build and run the app
```

## Architecture

MVC pattern with delegation-based communication between components.

```
Sources/Notes/
├── App/          # AppDelegate, MainWindowController
├── Models/       # Note (value type), NoteStore (file I/O + directory watching)
├── Views/        # SidebarViewController, EditorViewController, NoteEditorTextView
├── Markdown/     # MarkdownFormatter (AST walker → NSAttributedString)
└── Utilities/    # Debouncer
```

## License

[MIT](LICENSE)
