import Foundation

// MARK: - IOSTransforms

/// Built-in transforms available on iOS.
///
/// The Mac app's `TransformRegistry` additionally merges marketplace/custom
/// JS transforms; iOS v1 ships the built-in set only, so we avoid pulling the
/// JavaScriptCore marketplace stack into the iOS targets.
enum IOSTransforms {

    /// The complete ordered list of transforms shown on iOS.
    static var all: [any Transform] {
        [
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
            JWTDecodeTransform(),

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
    }
}
