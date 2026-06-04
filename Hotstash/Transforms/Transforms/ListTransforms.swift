import Foundation

// MARK: - SortAZTransform

struct SortAZTransform: Transform {
    let id       = "sort_az"
    let name     = "Sort A → Z"
    let icon     = "arrow.up.and.down.text.horizontal"
    let category = TransformCategory.lists

    let applicableTo: [ContentType] = [.list]

    /// Splits the input into lines and sorts them ascending (case-insensitive,
    /// locale-aware). Empty trailing newlines are preserved as empty strings
    /// at the end so the round-trip is lossless where possible.
    func apply(to input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        let sorted = lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return sorted.joined(separator: "\n")
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
    /// locale-aware).
    func apply(to input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        let sorted = lines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
        return sorted.joined(separator: "\n")
    }
}
