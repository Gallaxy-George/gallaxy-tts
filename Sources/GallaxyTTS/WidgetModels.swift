import AppKit
import Carbon
import QuartzCore
import SwiftUI

enum WidgetPlayResult {
    case selection(String)
    case clipboard(String)
    case empty
}

struct ClipboardClip: Identifiable, Codable {
    let id: UUID
    let text: String
    let source: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.source = source
        self.createdAt = createdAt
    }

    var title: String {
        let words = normalizedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .prefix(3)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "CLIP" : title.uppercased()
    }

    var preview: String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
        let preview = lines.joined(separator: " / ")
        guard !preview.isEmpty else { return "(empty)" }
        return preview.count > 94 ? String(preview.prefix(91)) + "..." : preview
    }

    private var normalizedText: String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "https://", with: " ")
            .replacingOccurrences(of: "http://", with: " ")
    }
}
