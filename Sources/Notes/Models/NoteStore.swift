import Foundation

protocol NoteStoreDelegate: AnyObject {
    func noteStoreDidUpdate(_ store: NoteStore)
}

class NoteStore {
    private(set) var notes: [Note] = []
    weak var delegate: NoteStoreDelegate?

    private let fileManager = FileManager.default
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var isSaving = false

    var notesDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: "NotesDirectory") {
                return URL(fileURLWithPath: path)
            }
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            return docs.appendingPathComponent("Notes")
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: "NotesDirectory")
        }
    }

    var assetsDirectory: URL {
        notesDirectory.appendingPathComponent("assets")
    }

    init() {
        ensureDirectoryExists()
        loadNotes()
        startWatching()
    }

    deinit {
        stopWatching()
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: notesDirectory.path) {
            try? fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        }
    }

    func loadNotes() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        notes = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Note? in
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                      let modDate = attrs[.modificationDate] as? Date else { return nil }
                let title = Note.extractTitle(from: content)
                return Note(fileURL: url, title: title, body: content, modifiedDate: modDate)
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    @discardableResult
    func createNote() -> Note {
        ensureDirectoryExists()
        let fileName = "Untitled \(dateString()).md"
        let url = notesDirectory.appendingPathComponent(fileName)
        let body = "# New Note\n\n"
        let note = Note(fileURL: url, title: "New Note", body: body)

        isSaving = true
        try? body.write(to: url, atomically: true, encoding: .utf8)
        isSaving = false

        notes.insert(note, at: 0)
        delegate?.noteStoreDidUpdate(self)
        return note
    }

    func save(note: Note) {
        isSaving = true
        try? note.body.write(to: note.fileURL, atomically: true, encoding: .utf8)
        isSaving = false

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            // Re-sort by modification date
            notes.sort { $0.modifiedDate > $1.modifiedDate }
        }
    }

    func delete(note: Note) {
        do {
            try fileManager.trashItem(at: note.fileURL, resultingItemURL: nil)
        } catch {
            try? fileManager.removeItem(at: note.fileURL)
        }
        notes.removeAll { $0.id == note.id }
        delegate?.noteStoreDidUpdate(self)
    }

    @discardableResult
    func saveImageToAssets(data: Data, suggestedName: String) -> String? {
        let assetsDir = assetsDirectory
        if !fileManager.fileExists(atPath: assetsDir.path) {
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }

        var filename = suggestedName
        let ext = (suggestedName as NSString).pathExtension
        let base = (suggestedName as NSString).deletingPathExtension
        var counter = 1
        while fileManager.fileExists(atPath: assetsDir.appendingPathComponent(filename).path) {
            filename = "\(base)_\(counter).\(ext)"
            counter += 1
        }

        let fileURL = assetsDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return "assets/\(filename)"
        } catch {
            return nil
        }
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - File Watching

    private func startWatching() {
        let path = notesDirectory.path
        directoryFD = open(path, O_EVTONLY)
        guard directoryFD >= 0 else { return }

        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: .write,
            queue: .main
        )

        directorySource?.setEventHandler { [weak self] in
            guard let self = self, !self.isSaving else { return }
            self.loadNotes()
            self.delegate?.noteStoreDidUpdate(self)
        }

        directorySource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }

        directorySource?.resume()
    }

    private func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }
}
