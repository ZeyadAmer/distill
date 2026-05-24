import Foundation

// MARK: - TrimWhitespaceTransform

struct TrimWhitespaceTransform: Transform {
    let id       = "trim_whitespace"
    let name     = "Trim Whitespace"
    let icon     = "arrow.left.and.right.text.vertical"
    let category = TransformCategory.whitespace

    let applicableTo: [ContentType] = []

    /// Trims leading/trailing whitespace on every line and collapses
    /// consecutive internal spaces/tabs on each line to a single space.
    func apply(to input: String) -> String {
        input.components(separatedBy: "\n")
            .map { line in
                line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}

// MARK: - RemoveBlankLinesTransform

struct RemoveBlankLinesTransform: Transform {
    let id       = "remove_blank_lines"
    let name     = "Remove Blank Lines"
    let icon     = "text.badge.minus"
    let category = TransformCategory.whitespace

    let applicableTo: [ContentType] = []

    /// Splits by newline, removes lines that are empty or contain only
    /// whitespace, then rejoins with a single newline.
    func apply(to input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return nonEmpty.joined(separator: "\n")
    }
}

// MARK: - RemoveDuplicateLinesTransform

struct RemoveDuplicateLinesTransform: Transform {
    let id       = "remove_duplicate_lines"
    let name     = "Remove Duplicate Lines"
    let icon     = "doc.on.doc"
    let category = TransformCategory.whitespace

    let applicableTo: [ContentType] = []

    /// Preserves original line order; removes subsequent occurrences of a
    /// line that has already been seen. Comparison is case-sensitive.
    func apply(to input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        var seen  = Set<String>()
        var result: [String] = []
        result.reserveCapacity(lines.count)

        for line in lines {
            if seen.insert(line).inserted {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }
}

// MARK: - RemoveLineBreaksTransform

struct RemoveLineBreaksTransform: Transform {
    let id       = "remove_line_breaks"
    let name     = "Remove Line Breaks"
    let icon     = "arrow.right.to.line.compact"
    let category = TransformCategory.whitespace

    let applicableTo: [ContentType] = []

    /// Replaces every newline with a single space, then collapses runs of
    /// multiple consecutive spaces down to one space.
    func apply(to input: String) -> String {
        let singleLine = input.replacingOccurrences(of: "\n", with: " ")

        // Collapse multiple spaces using a simple component-based approach
        // to avoid a regex dependency in this file.
        let words = singleLine.components(separatedBy: " ").filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }
}
