import Foundation

// MARK: - TransformRegistry

/// Central registry that owns every available transform instance.
/// Use `TransformRegistry.shared` everywhere — instantiating transforms
/// ad-hoc is intentionally avoided so the registry can own ordering.
final class TransformRegistry {

    // MARK: Singleton

    static let shared = TransformRegistry()
    private init() {}

    // MARK: All Transforms

    /// The complete ordered list of all registered transforms.
    let all: [any Transform] = [
        // Case
        ToUppercaseTransform(),
        ToLowercaseTransform(),
        ToTitleCaseTransform(),
        ToSentenceCaseTransform(),

        // Whitespace
        TrimWhitespaceTransform(),
        RemoveBlankLinesTransform(),
        RemoveDuplicateLinesTransform(),
        RemoveLineBreaksTransform(),

        // Lists
        SortAZTransform(),
        SortZATransform(),

        // JSON
        FormatJSONTransform(),
        MinifyJSONTransform(),

        // Encoding
        Base64EncodeTransform(),
        Base64DecodeTransform(),
        URLEncodeTransform(),
        URLDecodeTransform(),

        // Cleanup
        ExtractURLsTransform(),
        StripHTMLTransform(),
        RemoveMarkdownTransform(),
        WordCountTransform(),

        // Wrap
        WrapInBackticksTransform(),
        WrapInQuotesTransform(),
        WrapInBracketsTransform(),
    ]

    // MARK: Enabled Transforms

    /// Returns only the transforms that the user has not disabled in Settings.
    /// Falls through to `all` when the user has no disabled transforms.
    var enabled: [any Transform] {
        let disabledIDs = Set(
            UserDefaults.standard.stringArray(forKey: "disabledTransformIDs") ?? []
        )
        guard !disabledIDs.isEmpty else { return all }
        return all.filter { !disabledIDs.contains($0.id) }
    }

    // MARK: Suggested Transforms

    /// Returns the top 3 most relevant transforms for a detected content type.
    /// Only considers transforms that are currently enabled.
    /// The first three suggestions are surfaced prominently in the picker.
    func suggested(for contentType: ContentType) -> [any Transform] {
        let suggestedIDs: [String]

        switch contentType {
        case .json:
            suggestedIDs = [
                FormatJSONTransform().id,
                MinifyJSONTransform().id,
                Base64EncodeTransform().id,
            ]
        case .list:
            suggestedIDs = [
                SortAZTransform().id,
                RemoveDuplicateLinesTransform().id,
                RemoveBlankLinesTransform().id,
            ]
        case .url:
            suggestedIDs = [
                ExtractURLsTransform().id,
                Base64EncodeTransform().id,
                URLEncodeTransform().id,
            ]
        case .code:
            suggestedIDs = [
                WrapInBackticksTransform().id,
                TrimWhitespaceTransform().id,
                RemoveBlankLinesTransform().id,
            ]
        case .plainText:
            suggestedIDs = [
                TrimWhitespaceTransform().id,
                ToUppercaseTransform().id,
                ToTitleCaseTransform().id,
            ]
        }

        // Build the result in the declared order so the suggestion ordering
        // reflects the intent above, not the position in `all`.
        // Only include transforms that are currently enabled.
        let enabledSet = enabled
        let indexByID: [String: any Transform] = enabledSet.reduce(into: [:]) { dict, transform in
            dict[transform.id] = transform
        }

        return suggestedIDs.compactMap { indexByID[$0] }
    }

    // MARK: Filtered by Category

    /// Returns all transforms (enabled or not) belonging to the given category,
    /// preserving the order they appear in `all`.
    /// Used by Settings to show all transforms regardless of enabled state.
    func transforms(in category: TransformCategory) -> [any Transform] {
        all.filter { $0.category == category }
    }
}
