import Foundation

struct Note: Identifiable, Equatable {
    let id: UUID
    var fileURL: URL
    var title: String
    var body: String
    var modifiedDate: Date

    init(id: UUID = UUID(), fileURL: URL, title: String, body: String, modifiedDate: Date = Date()) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.body = body
        self.modifiedDate = modifiedDate
    }

    static func extractTitle(from body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Check for # heading
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            // Otherwise use first non-empty line
            return trimmed
        }
        return "Untitled"
    }

    var previewSnippet: String {
        let lines = body.components(separatedBy: .newlines)
        // Skip the title line, find next non-empty line
        var foundTitle = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if !foundTitle {
                foundTitle = true
                continue
            }
            // Strip markdown syntax for preview
            var preview = trimmed
            preview = preview.replacingOccurrences(of: "**", with: "")
            preview = preview.replacingOccurrences(of: "*", with: "")
            preview = preview.replacingOccurrences(of: "~~", with: "")
            preview = preview.replacingOccurrences(of: "`", with: "")
            if preview.hasPrefix("# ") || preview.hasPrefix("## ") || preview.hasPrefix("### ") {
                // Strip heading markers
                while preview.hasPrefix("#") { preview = String(preview.dropFirst()) }
                preview = preview.trimmingCharacters(in: .whitespaces)
            }
            let maxLen = 80
            if preview.count > maxLen {
                return String(preview.prefix(maxLen)) + "..."
            }
            return preview
        }
        return "No additional text"
    }
}
