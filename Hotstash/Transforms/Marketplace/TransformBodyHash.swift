import CryptoKit
import Foundation

/// Produces a stable SHA-256 hash of a transform's *body* only, ignoring all
/// surrounding manifest metadata (name, version, author, timestamps). Two transforms
/// with identical logic therefore share a hash, enabling deduplication.
enum TransformBodyHash {
    static func hash(_ body: TransformBody) -> String {
        let payload: Data
        switch body {
        case let .text(js):
            payload = Data("text:".utf8) + Data(js.utf8)
        case let .image(steps):
            let canonical = canonicalStepsData(steps)
            payload = Data("image:".utf8) + canonical
        }

        let digest = SHA256.hash(data: payload)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Encodes the steps array to deterministic JSON (sorted keys) for hashing.
    /// Falls back to an empty array encoding on the (unreachable) encode failure
    /// so hashing never throws.
    private static func canonicalStepsData(_ steps: [ImageStep]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(steps)) ?? Data("[]".utf8)
    }
}
