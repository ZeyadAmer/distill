import Foundation

// MARK: - TransformRegistry

/// Central registry that owns every available transform instance.
/// Use `TransformRegistry.shared` everywhere — instantiating transforms
/// ad-hoc is intentionally avoided so the registry can own ordering.
final class TransformRegistry {

    // MARK: Singleton

    static let shared = TransformRegistry()
    private init() {}

    /// Test-only initializer that injects a custom-transforms provider without
    /// touching the shared singleton. Production always uses `shared`.
    internal init(customProvider: @escaping () -> [any Transform]) {
        self.customProvider = customProvider
    }

    // MARK: Custom Transform Source

    /// Provides installed/custom transforms to merge with the built-ins.
    /// Defaults to the marketplace library; overridable in tests.
    ///
    /// All registry accessors run on the main thread (every call site is
    /// main-thread UI), so reading the `@MainActor` library via
    /// `MainActor.assumeIsolated` is safe here and keeps the accessors free of
    /// actor annotations.
    var customProvider: () -> [any Transform] = {
        MainActor.assumeIsolated { MarketplaceLibrary.shared.customTransforms() }
    }

    // MARK: Merge

    /// Merges built-in and custom transforms. On id/slug collision the built-in wins
    /// (the custom one is dropped) so a community transform can never shadow a built-in.
    static func merge(builtIn: [any Transform], custom: [any Transform]) -> [any Transform] {
        let builtInIDs = Set(builtIn.map { $0.id })
        let safeCustom = custom.filter { !builtInIDs.contains($0.id) }
        return builtIn + safeCustom
    }

    /// Built-ins plus installed/custom transforms, with built-ins taking precedence.
    private var allMerged: [any Transform] {
        Self.merge(builtIn: all, custom: customProvider())
    }

    // MARK: All Transforms

    /// The complete ordered list of all registered transforms.
    var all: [any Transform] {
        var transforms: [any Transform] = [
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
            CleanLinkTransform(),
            ExtractURLsTransform(),
            StripHTMLTransform(),
            RemoveMarkdownTransform(),
            WordCountTransform(),

            // Wrap
            WrapInBackticksTransform(),
            WrapInQuotesTransform(),
            WrapInBracketsTransform(),
        ]
        #if os(macOS)
        transforms.append(RuffFormatTransform())
        transforms += [
            ResizeHalfTransform(),
            GrayscaleTransform(),
            ConvertToPNGTransform(),
            ConvertToWebPTransform(),
            FlipHorizontalTransform(),
            Rotate90Transform(),
        ]
        #endif
        return transforms
    }

    // MARK: Custom-Ordered Transforms

    /// All transforms (built-in + installed/custom) in the user's custom order
    /// (falls back to default order). Newly installed transforms not yet in the
    /// saved order are appended at the end.
    var orderedAll: [any Transform] {
        let merged = allMerged
        let customOrder = UserDefaults.standard.stringArray(forKey: "transformOrder") ?? []
        guard !customOrder.isEmpty else { return merged }
        let byID = merged.reduce(into: [String: any Transform]()) { $0[$1.id] = $1 }
        var result: [any Transform] = customOrder.compactMap { byID[$0] }
        // Append any transforms added (or installed) after the order was last saved.
        let knownIDs = Set(customOrder)
        result += merged.filter { !knownIDs.contains($0.id) }
        return result
    }

    /// Saves a new global order (array of transform IDs) to UserDefaults.
    func saveOrder(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: "transformOrder")
    }

    // MARK: Enabled Transforms

    /// Returns only the transforms that the user has not disabled, in the user's order.
    var enabled: [any Transform] {
        let disabledIDs = Set(
            UserDefaults.standard.stringArray(forKey: "disabledTransformIDs") ?? []
        )
        guard !disabledIDs.isEmpty else { return orderedAll }
        return orderedAll.filter { !disabledIDs.contains($0.id) }
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
                CleanLinkTransform().id,
                ExtractURLsTransform().id,
                URLEncodeTransform().id,
            ]
        case .code:
            suggestedIDs = [
                WrapInBackticksTransform().id,
                TrimWhitespaceTransform().id,
                RemoveBlankLinesTransform().id,
            ]
        case .image:
            #if os(macOS)
            suggestedIDs = [
                ResizeHalfTransform().id,
                GrayscaleTransform().id,
                Rotate90Transform().id,
            ]
            #else
            suggestedIDs = []
            #endif
        case .file:
            suggestedIDs = []
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

    /// Returns all transforms belonging to the given category in the user's custom order.
    func transforms(in category: TransformCategory) -> [any Transform] {
        orderedAll.filter { $0.category == category }
    }
}
