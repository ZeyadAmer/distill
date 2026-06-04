import Foundation

// MARK: - Base64EncodeTransform

struct Base64EncodeTransform: Transform {
    let id       = "base64_encode"
    let name     = "Base64 Encode"
    let icon     = "lock.doc"
    let category = TransformCategory.encoding

    let applicableTo: [ContentType] = []

    func apply(to input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }
}

// MARK: - Base64DecodeTransform

struct Base64DecodeTransform: Transform {
    let id       = "base64_decode"
    let name     = "Base64 Decode"
    let icon     = "lock.open"
    let category = TransformCategory.encoding

    let applicableTo: [ContentType] = []

    /// Attempts to decode the input as a Base64 string and convert the
    /// resulting bytes to a UTF-8 string. Returns the original input if
    /// the input is not valid Base64 or cannot be represented as UTF-8.
    func apply(to input: String) -> String {
        // Base64 strings may contain whitespace/newlines when copied from
        // terminals or documents — strip them before attempting decode.
        let stripped = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let data   = Data(base64Encoded: stripped, options: .ignoreUnknownCharacters),
            let result = String(data: data, encoding: .utf8)
        else {
            return input
        }
        return result
    }
}

// MARK: - URLEncodeTransform

struct URLEncodeTransform: Transform {
    let id       = "url_encode"
    let name     = "URL Encode"
    let icon     = "link.badge.plus"
    let category = TransformCategory.encoding

    let applicableTo: [ContentType] = []

    /// Percent-encodes the input using the URL query allowed character set,
    /// which encodes spaces as `%20` and leaves unreserved characters intact.
    func apply(to input: String) -> String {
        input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
    }
}

// MARK: - URLDecodeTransform

struct URLDecodeTransform: Transform {
    let id       = "url_decode"
    let name     = "URL Decode"
    let icon     = "link"
    let category = TransformCategory.encoding

    let applicableTo: [ContentType] = []

    /// Decodes percent-encoded characters in the input string.
    /// Returns the original input if decoding is not possible.
    func apply(to input: String) -> String {
        input.removingPercentEncoding ?? input
    }
}

// MARK: - JWTDecodeTransform

struct JWTDecodeTransform: Transform {
    let id       = "jwt_decode"
    let name     = "Decode JWT"
    let icon     = "person.badge.key"
    let category = TransformCategory.encoding

    let applicableTo: [ContentType] = []

    func apply(to input: String) -> String {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return input }

        guard
            let header  = decodeSegment(parts[0]),
            let payload = decodeSegment(parts[1])
        else { return input }

        let combined: [String: Any] = ["header": header, "payload": payload]
        guard
            let data   = try? JSONSerialization.data(withJSONObject: combined, options: [.prettyPrinted, .sortedKeys]),
            let result = String(data: data, encoding: .utf8)
        else { return input }

        return result
    }

    // base64url → standard base64 with padding → decoded JSON object
    private func decodeSegment(_ segment: String) -> Any? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard
            let data   = Data(base64Encoded: base64),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        return object
    }
}
