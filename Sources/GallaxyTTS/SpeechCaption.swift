import Foundation

struct SpeechCaption: Codable, Equatable {
    let text: String
    let start: TimeInterval

    static func load(for audioURL: URL) -> [SpeechCaption] {
        let url = audioURL.deletingPathExtension().appendingPathExtension("captions.json")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url),
              let cues = try? JSONDecoder().decode([SpeechCaption].self, from: data),
              cues.allSatisfy({ $0.start.isFinite && $0.start >= 0 && !$0.text.isEmpty }),
              zip(cues, cues.dropFirst()).allSatisfy({ $0.start <= $1.start }) else { return [] }
        return cues
    }

    static func phrases(in text: String) -> [(text: String, range: NSRange)] {
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\S+\s*"#)
        var phrases: [(text: String, range: NSRange)] = []
        var current: NSRange?
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if let range = current, range.length + match.range.length > 42 {
                phrases.append((source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines), range))
                current = nil
            }
            current = current.map { NSUnionRange($0, match.range) } ?? match.range
            let word = source.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"”’)]"))
            if let last = word.last, ".!?;:,".contains(last), let range = current {
                phrases.append((source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines), range))
                current = nil
            }
        }
        if let range = current {
            phrases.append((source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines), range))
        }
        return phrases
    }

    // Used only by audio providers without alignment metadata. Approximate,
    // proportional phrase timing, anchored to the actual file duration/clock.
    static func estimated(text: String, duration: TimeInterval) -> [SpeechCaption] {
        let phrases = phrases(in: text)
        let total = Double(phrases.reduce(0) { $0 + $1.range.length })
        var offset = 0.0
        return phrases.map { phrase in
            defer { offset += Double(phrase.range.length) }
            return SpeechCaption(text: phrase.text, start: duration * offset / max(1, total))
        }
    }
}
