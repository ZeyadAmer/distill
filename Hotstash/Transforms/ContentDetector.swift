import Foundation

// MARK: - ContentType

enum ContentType: String, Codable, CaseIterable {
    case json
    case url
    case code
    case list
    case image
    case file
    case plainText
}

// MARK: - ContentDetector

struct ContentDetector {

    // MARK: - Public API

    /// Detects the most likely content type for the given string.
    static func detect(_ text: String) -> ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plainText }

        if isJSON(trimmed)      { return .json }
        if isURL(trimmed)       { return .url }
        if isCode(trimmed)      { return .code }
        if isList(trimmed)      { return .list }
        return .plainText
    }

    // MARK: - Private Detectors

    /// Returns true when the trimmed string looks like valid JSON.
    private static func isJSON(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    /// Returns true when the string starts with an http or https scheme.
    private static func isURL(_ trimmed: String) -> Bool {
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    /// Returns true when several code-like tokens appear in the text.
    /// Scoring: each matched token adds 1 point; threshold is > 2.
    private static func isCode(_ text: String) -> Bool {
        let tokens: [String] = [
            "{", "}", ";",
            "func ", "def ", "var ", "let ", "const ",
            "class ", "import "
        ]
        let score = tokens.reduce(0) { count, token in
            count + (text.contains(token) ? 1 : 0)
        }
        return score > 2
    }

    /// Returns true when the text contains at least two newlines,
    /// implying a multi-line list structure.
    private static func isList(_ text: String) -> Bool {
        let newlineCount = text.components(separatedBy: "\n").count - 1
        return newlineCount >= 2
    }
}
