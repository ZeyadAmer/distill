import Foundation

// MARK: - ToUppercaseTransform

struct ToUppercaseTransform: Transform {
    let id       = "to_uppercase"
    let name     = "UPPERCASE"
    let icon     = "characters.uppercase"
    let category = TransformCategory.casing

    /// Works on all content types — no restriction.
    let applicableTo: [ContentType] = []

    func apply(to input: String) -> String {
        input.uppercased()
    }
}

// MARK: - ToLowercaseTransform

struct ToLowercaseTransform: Transform {
    let id       = "to_lowercase"
    let name     = "lowercase"
    let icon     = "characters.lowercase"
    let category = TransformCategory.casing

    let applicableTo: [ContentType] = []

    func apply(to input: String) -> String {
        input.lowercased()
    }
}

// MARK: - ToTitleCaseTransform

struct ToTitleCaseTransform: Transform {
    let id       = "to_title_case"
    let name     = "Title Case"
    let icon     = "textformat"
    let category = TransformCategory.casing

    let applicableTo: [ContentType] = [.plainText]

    /// Capitalizes the first letter of every word using Swift's built-in
    /// `capitalized` property, which handles Unicode correctly.
    func apply(to input: String) -> String {
        input.capitalized
    }
}

// MARK: - ToSentenceCaseTransform

struct ToSentenceCaseTransform: Transform {
    let id       = "to_sentence_case"
    let name     = "Sentence case"
    let icon     = "textformat.characters"
    let category = TransformCategory.casing

    let applicableTo: [ContentType] = [.plainText]

    /// Lowercases the entire string, then uppercases only the very first character.
    func apply(to input: String) -> String {
        let lowered = input.lowercased()
        guard let first = lowered.first else { return lowered }
        return first.uppercased() + lowered.dropFirst()
    }
}
