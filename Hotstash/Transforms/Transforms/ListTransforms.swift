import Foundation

/// Sorts the content lines of `input`, preserving a single trailing newline.
/// A trailing "\n" would otherwise split into an empty last element that sorts
/// ahead of every real line, producing a spurious leading blank line.
private func sortedLines(
    _ input: String,
    by areInIncreasingOrder: (String, String) -> Bool
) -> String {
    let hadTrailingNewline = input.hasSuffix("\n")
    let body = hadTrailingNewline ? String(input.dropLast()) : input
    let sorted = body.components(separatedBy: "\n").sorted(by: areInIncreasingOrder)
    let joined = sorted.joined(separator: "\n")
    return hadTrailingNewline ? joined + "\n" : joined
}

// MARK: - SortAZTransform

struct SortAZTransform: Transform {
    let id       = "sort_az"
    let name     = "Sort A → Z"
    let icon     = "arrow.up.and.down.text.horizontal"
    let category = TransformCategory.lists

    let applicableTo: [ContentType] = [.list]

    /// Splits the input into lines and sorts them ascending (case-insensitive,
    /// locale-aware). A trailing newline is preserved.
    func apply(to input: String) -> String {
        sortedLines(input) { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - SortZATransform

struct SortZATransform: Transform {
    let id       = "sort_za"
    let name     = "Sort Z → A"
    let icon     = "line.3.horizontal.decrease"
    let category = TransformCategory.lists

    let applicableTo: [ContentType] = [.list]

    /// Splits the input into lines and sorts them descending (case-insensitive,
    /// locale-aware). A trailing newline is preserved.
    func apply(to input: String) -> String {
        sortedLines(input) { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
    }
}
