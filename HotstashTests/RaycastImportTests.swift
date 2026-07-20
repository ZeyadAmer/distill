import Testing
import Foundation
import SwiftData
@testable import Hotstash

// Synthetic .rayconfig built with the real Raycast scheme
// (AES-256-CBC, no salt, SHA-256 key derivation, 16-byte header + gzip JSON).
// Passphrase: "test1234". Contains 5 records: two identical "hello world"
// text items, one link, one image-with-OCR, one image with empty text.
private let fixtureBase64 = "aC0zqLU1XktZikTica9JutsrjAmvIkgv4NfHlznt+3JdOFNHLOVmUqUQUWIj63gMY2pwK3eY1UL6iZ7iEU7pBKYAMMhAQ8j9jqhKu2umD0gtem6vKZVQpbelGdT4QiBEfc6wKj1ujWHqR8IoTKhIC70orUuQwBoC7UIC8MHFnc2YtEuM512NdosS3bY0m19C1jkb93iIbhxyffZQgrAgWm1t7anUpiMrHNLXKt1IL8YX6WKbNG6XM3SVAnylut7zob9UmGri7YtCGH43YA71axUgG+XsJxKaKrh4jgk9cFWEBr70PyXQCXwwTXBtqgPHCgbfKaG6mVMgzqvpvk5vuA=="

@MainActor
struct RaycastImportTests {

    private let container: ModelContainer
    private let store: ClipboardStore

    init() throws {
        container = try ModelContainer.hotstashInMemory()
        store = ClipboardStore(container: container)
    }

    private func writeFixture() throws -> URL {
        let data = Data(base64Encoded: fixtureBase64)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).rayconfig")
        try data.write(to: url)
        return url
    }

    @Test("Imports clipboard records, mapping category and de-duplicating content")
    func importsAndDeduplicates() throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let count = try RaycastImporter.importClipboard(from: url, passphrase: "test1234", into: store)

        // 5 records → 3 items: duplicate "hello world" collapses, empty image skipped.
        #expect(count == 3)

        let items = store.items
        #expect(items.contains { $0.content == "hello world" && $0.contentType == .plainText })
        #expect(items.contains { $0.content == "https://example.com/path" && $0.contentType == .url })

        let ocr = items.first { $0.content == "OCR from image" }
        #expect(ocr?.ocrText == "OCR from image")
        #expect(!items.contains { $0.content.isEmpty })
    }

    @Test("Re-importing the same export adds nothing")
    func reimportIsIdempotent() throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try RaycastImporter.importClipboard(from: url, passphrase: "test1234", into: store)
        let second = try RaycastImporter.importClipboard(from: url, passphrase: "test1234", into: store)
        #expect(second == 0)
    }

    @Test("A wrong passphrase throws instead of importing garbage")
    func wrongPassphraseThrows() throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RaycastImportError.self) {
            try RaycastImporter.importClipboard(from: url, passphrase: "wrong-passphrase", into: store)
        }
    }
}
