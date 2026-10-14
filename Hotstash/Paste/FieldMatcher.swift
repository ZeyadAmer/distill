import Foundation

// MARK: - FieldMatcher

/// Picks which Paste Stack item belongs in the focused form field.
///
/// The field is described by its accessibility text (label, placeholder,
/// identifier…). An item matches when its user-assigned label appears in that
/// text, or when the field asks for a kind of value (email, phone, URL) that
/// the item's content clearly is.
enum FieldMatcher {

    enum Kind { case email, phone, url }

    /// Index of the first candidate that fits the field, or nil to keep stack order.
    static func bestIndex(fieldText: String, candidates: [(content: String, label: String)]) -> Int? {
        let field = normalized(fieldText)
        guard !field.isEmpty else { return nil }

        if let i = candidates.firstIndex(where: { candidate in
            let label = normalized(candidate.label)
            return label.count >= 2 && field.contains(label)
        }) {
            return i
        }

        guard let wanted = kind(ofField: field) else { return nil }
        return candidates.firstIndex { kind(ofContent: $0.content) == wanted }
    }

    static func kind(ofField text: String) -> Kind? {
        let t = normalized(text)
        if t.contains("email") { return .email }
        if t.contains("phone") || t.contains("mobile") || t.hasPrefix("tel") { return .phone }
        if t.contains("website") || t.contains("url") || t.contains("homepage") { return .url }
        return nil
    }

    static func kind(ofContent content: String) -> Kind? {
        let s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil { return .email }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return .url }
        let digits = s.filter(\.isNumber).count
        if s.range(of: #"^\+?[0-9 ()\-.]+$"#, options: .regularExpression) != nil, (7...15).contains(digits) {
            return .phone
        }
        return nil
    }

    /// Lowercased letters and digits only, so "E-mail Address" → "emailaddress".
    private static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }
}
