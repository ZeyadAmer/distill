import Foundation

// MARK: - Transform Category

enum TransformCategory: String, CaseIterable {
    case casing     = "Case"
    case whitespace = "Whitespace"
    case lists      = "Lists"
    case json       = "JSON"
    case encoding   = "Encoding"
    case cleanup    = "Cleanup"
    case wrap       = "Wrap"
}

// MARK: - Transform Protocol

/// A Transform takes a string, performs a single well-defined operation,
/// and returns the result. Transforms must never crash; on failure they
/// return the original input unchanged.
protocol Transform {
    /// Unique snake_case identifier, stable across app versions.
    var id: String { get }

    /// Human-readable label shown in the UI.
    var name: String { get }

    /// SF Symbol name used as the transform icon.
    var icon: String { get }

    /// The category this transform belongs to (used for grouping in the picker).
    var category: TransformCategory { get }

    /// Content types this transform is applicable to.
    /// An empty array means the transform works on all content types.
    var applicableTo: [ContentType] { get }

    /// Applies the transform to `input` and returns the result.
    /// Must never throw or crash — return `input` unchanged on any failure.
    func apply(to input: String) -> String
}
