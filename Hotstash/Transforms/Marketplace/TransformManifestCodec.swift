import Foundation

/// Deterministic JSON codec for `TransformManifest`. Uses ISO8601 dates and sorted
/// keys so encoded output is stable for hashing, diffing, and storage.
enum TransformManifestCodec {
    static func encode(_ manifest: TransformManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(manifest)
    }

    static func decode(_ data: Data) throws -> TransformManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TransformManifest.self, from: data)
    }

    static func decode(json: String) throws -> TransformManifest {
        guard let data = json.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "JSON string is not valid UTF-8")
            )
        }
        return try decode(data)
    }
}
