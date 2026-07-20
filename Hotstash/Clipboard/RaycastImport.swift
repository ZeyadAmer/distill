import Foundation
import OSLog
import CommonCrypto
import Compression

// MARK: - RaycastImportError

enum RaycastImportError: LocalizedError {
    case unreadableFile
    case decryptionFailed
    case noClipboardHistory

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Couldn't read the .rayconfig file."
        case .decryptionFailed:
            return "Couldn't decrypt the export. Check the passphrase and try again."
        case .noClipboardHistory:
            return "This export doesn't contain any clipboard history."
        }
    }
}

// MARK: - RaycastImporter

/// Imports clipboard history from a Raycast `Export Settings & Data` file
/// (`.rayconfig`). The user supplies the file (via a picker) and the passphrase
/// they set during export — nothing is read silently.
///
/// Format: AES-256-CBC (no salt, key/IV derived from the passphrase via
/// OpenSSL's EVP_BytesToKey with SHA-256), a 16-byte Raycast header, then a
/// gzip stream wrapping the config JSON.
enum RaycastImporter {

    private static let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "RaycastImport")

    /// Decrypts, parses, and inserts Raycast clipboard history. Returns the
    /// number of items actually added (after de-duplication against existing
    /// history). Throws `RaycastImportError` on failure.
    @MainActor
    @discardableResult
    static func importClipboard(
        from url: URL,
        passphrase: String,
        into store: ClipboardStore = .shared
    ) throws -> Int {
        let items = try clipboardItems(from: url, passphrase: passphrase)
        return store.importItems(items)
    }

    // MARK: Decode

    /// Produces `ClipboardItem`s from the export without inserting them.
    @MainActor
    static func clipboardItems(from url: URL, passphrase: String) throws -> [ClipboardItem] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let encrypted = try? Data(contentsOf: url) else {
            throw RaycastImportError.unreadableFile
        }
        guard let json = decryptToJSON(encrypted, passphrase: passphrase) else {
            throw RaycastImportError.decryptionFailed
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let history = root["builtin_package_clipboardHistory"] as? [String: Any],
            let records = history["clipboardHistoryRecords"] as? [[String: Any]]
        else {
            throw RaycastImportError.noClipboardHistory
        }
        return records.compactMap(makeItem)
    }

    /// Maps one Raycast record to a `ClipboardItem`, or nil to skip it.
    private static func makeItem(_ record: [String: Any]) -> ClipboardItem? {
        // Raycast's `text` holds the textual content for text/link records and
        // the OCR/filename text for image/file records.
        let text = (record["text"] as? String) ?? ""
        guard !text.isEmpty else { return nil }

        let category = (record["category"] as? String) ?? "text"
        let timestamp = date(record["createdAt"] as? String)
        let useCount = (record["copyCount"] as? Int) ?? 0

        switch category {
        case "link":
            return ClipboardItem(
                content: text, contentType: .url,
                timestamp: timestamp, useCount: useCount
            )

        case "image":
            // Image bytes live in Raycast's cache and are not bundled in the
            // export, so import the OCR text as a text item (searchable).
            return ClipboardItem(
                content: text, contentType: ContentDetector.detect(text),
                timestamp: timestamp, useCount: useCount, ocrText: text
            )

        default: // "text" and "file" (filename)
            let rtf = (record["richText"] as? String).flatMap { Data(base64Encoded: $0) }
            return ClipboardItem(
                content: text, contentType: ContentDetector.detect(text),
                timestamp: timestamp, useCount: useCount, rtfData: rtf
            )
        }
    }

    private static func date(_ iso: String?) -> Date {
        guard let iso else { return .now }
        return ISO8601DateFormatter().date(from: iso) ?? .now
    }

    // MARK: Crypto

    /// AES-256-CBC decrypt → strip 16-byte Raycast header + gzip → JSON bytes.
    /// Returns nil on any failure (wrong passphrase or malformed input).
    private static func decryptToJSON(_ encrypted: Data, passphrase: String) -> Data? {
        let (key, iv) = deriveKeyIV(passphrase)
        guard let plain = aesCBCDecrypt(encrypted, key: key, iv: iv),
              plain.count > 26 else { return nil }
        // 16-byte Raycast header + 10-byte gzip header (flags = 0, no extras).
        let deflate = plain.subdata(in: 26..<plain.count)
        return inflateRawDeflate(deflate)
    }

    /// OpenSSL EVP_BytesToKey (SHA-256, no salt): 32-byte key + 16-byte IV.
    private static func deriveKeyIV(_ passphrase: String) -> (Data, Data) {
        let pw = Array(passphrase.utf8)
        var material = [UInt8]()
        var previous = [UInt8]()
        while material.count < 48 {
            var ctx = CC_SHA256_CTX()
            CC_SHA256_Init(&ctx)
            CC_SHA256_Update(&ctx, previous, CC_LONG(previous.count))
            CC_SHA256_Update(&ctx, pw, CC_LONG(pw.count))
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256_Final(&digest, &ctx)
            material.append(contentsOf: digest)
            previous = digest
        }
        return (Data(material[0..<32]), Data(material[32..<48]))
    }

    private static func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { i in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, key.count, i.baseAddress,
                            d.baseAddress, data.count,
                            o.baseAddress, outCapacity, &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.removeSubrange(moved..<out.count)
        return out
    }

    /// Apple's `COMPRESSION_ZLIB` decodes a raw DEFLATE stream (RFC 1951),
    /// which is exactly the gzip body once the 10-byte header is removed.
    private static func inflateRawDeflate(_ data: Data) -> Data? {
        // Config JSON is a few MB; grow the buffer if a decode fills it exactly.
        var capacity = max(4_000_000, data.count * 12)
        while capacity <= 64_000_000 {
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            let produced = data.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
            guard produced > 0 else { return nil }
            if produced < capacity { return Data(bytes: dst, count: produced) }
            capacity *= 2 // filled exactly — may be truncated, retry larger
        }
        return nil
    }
}
