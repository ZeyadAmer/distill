import Foundation

// MARK: - FormatJSONTransform

struct FormatJSONTransform: Transform {
    let id       = "format_json"
    let name     = "Format JSON"
    let icon     = "curlybraces"
    let category = TransformCategory.json

    let applicableTo: [ContentType] = [.json]

    /// Parses the input as JSON and re-serialises it with `.prettyPrinted`.
    /// Returns the original string unchanged when the input is not valid JSON.
    func apply(to input: String) -> String {
        guard
            let data     = input.data(using: .utf8),
            let object   = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let pretty   = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let result   = String(data: pretty, encoding: .utf8)
        else {
            return input
        }
        return result
    }
}

// MARK: - MinifyJSONTransform

struct MinifyJSONTransform: Transform {
    let id       = "minify_json"
    let name     = "Minify JSON"
    let icon     = "curlybraces.square"
    let category = TransformCategory.json

    let applicableTo: [ContentType] = [.json]

    /// Parses the input as JSON and re-serialises it without any formatting
    /// options, producing the most compact representation.
    /// Returns the original string unchanged when the input is not valid JSON.
    func apply(to input: String) -> String {
        guard
            let data   = input.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let minified = try? JSONSerialization.data(withJSONObject: object, options: []),
            let result = String(data: minified, encoding: .utf8)
        else {
            return input
        }
        return result
    }
}
