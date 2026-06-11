import Foundation

// MARK: - IOSTransforms

/// Built-in transforms available on iOS.
///
/// The Mac app's `TransformRegistry` additionally merges marketplace/custom
/// JS transforms; iOS v1 ships the built-in set only, so we avoid pulling the
/// JavaScriptCore marketplace stack into the iOS targets.
enum IOSTransforms {

    /// Marketplace installs injected by the main app at launch. The keyboard
    /// and share extensions keep the empty default — no SwiftData there.
    static var extraProvider: () -> [any Transform] = { [] }

    /// Built-ins plus any installed marketplace transforms.
    static var all: [any Transform] { builtIns + extraProvider() }

    /// The built-in list shipped with the app.
    static var builtIns: [any Transform] {
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

// MARK: - IOSTransformSettings

/// User-controlled ordering and enablement for the iOS transforms, persisted
/// in the app-group defaults so the keyboard and share extensions follow the
/// same order the user sets in Settings → Transforms.
enum IOSTransformSettings {

    private static let orderKey = "ios.transformOrder"
    private static let disabledKey = "ios.disabledTransforms"

    /// All transforms in the user's saved order. Transforms added in app
    /// updates (not yet in the saved order) keep their built-in position at
    /// the end.
    static func orderedAll() -> [any Transform] {
        let saved = SharedDefaults.store.stringArray(forKey: orderKey) ?? []
        let all = IOSTransforms.all
        var remaining = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var result: [any Transform] = []
        for id in saved {
            if let transform = remaining.removeValue(forKey: id) {
                result.append(transform)
            }
        }
        result.append(contentsOf: all.filter { remaining[$0.id] != nil })
        return result
    }

    /// Enabled transforms in user order — what pickers and the keyboard show.
    static func enabledOrdered() -> [any Transform] {
        orderedAll().filter { isEnabled($0.id) }
    }

    static func isEnabled(_ id: String) -> Bool {
        !(SharedDefaults.store.stringArray(forKey: disabledKey) ?? []).contains(id)
    }

    static func setEnabled(_ id: String, _ enabled: Bool) {
        var disabled = SharedDefaults.store.stringArray(forKey: disabledKey) ?? []
        if enabled {
            disabled.removeAll { $0 == id }
        } else if !disabled.contains(id) {
            disabled.append(id)
        }
        SharedDefaults.store.set(disabled, forKey: disabledKey)
    }

    static func saveOrder(_ ids: [String]) {
        SharedDefaults.store.set(ids, forKey: orderKey)
    }
}
