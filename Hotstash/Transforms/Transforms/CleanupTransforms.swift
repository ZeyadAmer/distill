import Foundation

// MARK: - ExtractURLsTransform

struct ExtractURLsTransform: Transform {
    let id       = "extract_urls"
    let name     = "Extract URLs"
    let icon     = "link.circle"
    let category = TransformCategory.cleanup

    let applicableTo: [ContentType] = []

    /// Uses NSDataDetector to find all hyperlinks in the input and returns
    /// them joined by newlines. Returns the original input when no URLs are
    /// found or when the detector cannot be initialised.
    func apply(to input: String) -> String {
        guard
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else {
            return input
        }

        let range = NSRange(input.startIndex..., in: input)
        let matches = detector.matches(in: input, options: [], range: range)

        let urls: [String] = matches.compactMap { match in
            match.url?.absoluteString
        }

        guard !urls.isEmpty else { return input }
        return urls.joined(separator: "\n")
    }
}

// MARK: - StripHTMLTransform

struct StripHTMLTransform: Transform {
    let id       = "strip_html"
    let name     = "Strip HTML"
    let icon     = "chevron.left.forwardslash.chevron.right"
    let category = TransformCategory.cleanup

    let applicableTo: [ContentType] = []

    /// Removes all HTML tags using a simple regex, then decodes the most
    /// common named and numeric HTML entities.
    func apply(to input: String) -> String {
        // Remove tags — matches anything between < and >
        let stripped: String
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(input.startIndex..., in: input)
            stripped = regex.stringByReplacingMatches(
                in: input,
                options: [],
                range: range,
                withTemplate: ""
            )
        } else {
            stripped = input
        }

        return decodeHTMLEntities(stripped)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        // Named entities most frequently encountered in copied web content.
        let namedEntities: [(String, String)] = [
            ("&amp;",  "&"),
            ("&lt;",   "<"),
            ("&gt;",   ">"),
            ("&quot;", "\""),
            ("&#39;",  "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&laquo;", "«"),
            ("&raquo;", "»"),
            ("&copy;",  "©"),
            ("&reg;",   "®"),
            ("&trade;", "™"),
        ]

        var result = text
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric decimal entities: &#NNN;
        if let numericRegex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let nsResult = NSMutableString(string: result)
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = numericRegex.matches(in: nsResult as String, options: [], range: fullRange)

            // Process in reverse so replacement offsets stay valid.
            for match in matches.reversed() {
                guard
                    match.numberOfRanges == 2,
                    let codePoint = UInt32(nsResult.substring(with: match.range(at: 1))),
                    let scalar = Unicode.Scalar(codePoint)
                else { continue }
                nsResult.replaceCharacters(in: match.range, with: String(scalar))
            }
            result = nsResult as String
        }

        return result
    }
}

// MARK: - RemoveMarkdownTransform

struct RemoveMarkdownTransform: Transform {
    let id       = "remove_markdown"
    let name     = "Remove Markdown"
    let icon     = "minus.square"
    let category = TransformCategory.cleanup

    let applicableTo: [ContentType] = []

    /// Strips the most common Markdown formatting tokens, leaving plain text.
    func apply(to input: String) -> String {
        var result = input

        // Order matters: longer/more-specific patterns first to avoid
        // partial stripping leaving orphaned characters.

        // Fenced code blocks (```...```) — replace with just the inner content
        result = stripFencedCodeBlocks(result)

        // Inline code: `text` → text
        result = result.replacingOccurrences(of: "`", with: "")

        // Bold+italic: ***text*** or ___text___
        result = applyRegex(#"\*{3}(.+?)\*{3}"#, replacement: "$1", to: result)
        result = applyRegex(#"_{3}(.+?)_{3}"#,   replacement: "$1", to: result)

        // Bold: **text** or __text__
        result = applyRegex(#"\*{2}(.+?)\*{2}"#, replacement: "$1", to: result)
        result = applyRegex(#"_{2}(.+?)_{2}"#,   replacement: "$1", to: result)

        // Italic: *text* or _text_
        result = applyRegex(#"\*(.+?)\*"#, replacement: "$1", to: result)
        result = applyRegex(#"_(.+?)_"#,   replacement: "$1", to: result)

        // Strikethrough: ~~text~~
        result = applyRegex(#"~~(.+?)~~"#, replacement: "$1", to: result)

        // ATX headings: up to six # characters at the start of a line
        result = applyRegex(#"(?m)^#{1,6}\s+"#, replacement: "", to: result)

        // Blockquote markers: "> " at the start of a line
        result = applyRegex(#"(?m)^>\s?"#, replacement: "", to: result)

        // Unordered list markers: "- " or "* " or "+ " at start of line
        result = applyRegex(#"(?m)^[-*+]\s+"#, replacement: "", to: result)

        // Ordered list markers: "1. " etc at start of line
        result = applyRegex(#"(?m)^\d+\.\s+"#, replacement: "", to: result)

        // Horizontal rules: --- or *** or ___ on their own line
        result = applyRegex(#"(?m)^[-*_]{3,}\s*$"#, replacement: "", to: result)

        // Markdown links: [text](url) → text
        result = applyRegex(#"\[(.+?)\]\(.+?\)"#, replacement: "$1", to: result)

        // Markdown images: ![alt](url) → alt
        result = applyRegex(#"!\[(.+?)\]\(.+?\)"#, replacement: "$1", to: result)

        return result
    }

    // MARK: Helpers

    private func stripFencedCodeBlocks(_ text: String) -> String {
        applyRegex(#"(?s)```[^\n]*\n(.*?)```"#, replacement: "$1", to: text)
    }

    private func applyRegex(_ pattern: String, replacement: String, to text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}

// MARK: - WrapInBackticksTransform

struct WrapInBackticksTransform: Transform {
    let id       = "wrap_in_backticks"
    let name     = "Wrap in Backticks"
    let icon     = "chevron.left.chevron.right"
    let category = TransformCategory.wrap

    let applicableTo: [ContentType] = [.code, .plainText]

    /// Wraps the entire input in a pair of single backtick characters.
    func apply(to input: String) -> String {
        "`\(input)`"
    }
}

// MARK: - WrapInQuotesTransform

struct WrapInQuotesTransform: Transform {
    let id       = "wrap_in_quotes"
    let name     = "Wrap in Quotes"
    let icon     = "quote.bubble"
    let category = TransformCategory.wrap

    let applicableTo: [ContentType] = []

    /// Wraps the entire input in straight double-quote characters.
    func apply(to input: String) -> String {
        "\"\(input)\""
    }
}

// MARK: - WrapInBracketsTransform

struct WrapInBracketsTransform: Transform {
    let id       = "wrap_in_brackets"
    let name     = "Wrap in Brackets"
    let icon     = "square.on.square"
    let category = TransformCategory.wrap

    let applicableTo: [ContentType] = []

    /// Wraps the entire input in square brackets.
    func apply(to input: String) -> String {
        "[\(input)]"
    }
}

// MARK: - WordCountTransform

struct WordCountTransform: Transform {
    let id       = "word_count"
    let name     = "Word Count"
    let icon     = "number"
    let category = TransformCategory.cleanup

    let applicableTo: [ContentType] = []

    /// Returns a descriptive count string of the form "Words: X | Characters: Y".
    /// The output is intentionally not the original text — callers should
    /// display the result rather than paste it directly (though pasting works).
    func apply(to input: String) -> String {
        let characterCount = input.count

        // Word counting: split on whitespace+newlines and discard empty tokens.
        let words = input.components(separatedBy: .whitespacesAndNewlines)
                         .filter { !$0.isEmpty }
        let wordCount = words.count

        return "Words: \(wordCount) | Characters: \(characterCount)"
    }
}
