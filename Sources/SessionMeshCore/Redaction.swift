import Foundation

enum Redaction {
    static let maxTitleLength = 60

    static func sanitize(_ text: String) -> String {
        escape(stripControlCharacters(truncate(text, to: maxTitleLength)))
    }

    static func sanitizePath(_ path: String) -> String {
        escape(stripControlCharacters(path))
    }

    static func truncate(_ text: String, to maxLength: Int) -> String {
        text.count <= maxLength ? text : String(text.prefix(maxLength))
    }

    static func stripControlCharacters(_ text: String) -> String {
        String(text.filter { !$0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) })
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
