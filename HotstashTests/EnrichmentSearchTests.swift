import Testing
import Foundation
import SwiftData
@testable import Hotstash

@MainActor
struct EnrichmentSearchTests {

    private func makeStore() throws -> ClipboardStore {
        let container = try ModelContainer.hotstashInMemory()
        return ClipboardStore(container: container)
    }

    @Test func searchMatchesOCRTextInsideImages() throws {
        let store = try makeStore()
        let item = ClipboardItem(content: "[Image]", contentType: .image,
                                 imageData: Data([0xFF]))
        store.add(item: item)
        store.setOCRText(id: item.id, text: "Invoice 2026 total 450 EGP")

        #expect(store.search(query: "invoice").map(\.id) == [item.id])
        #expect(store.search(query: "nonsense").isEmpty)
    }

    @Test func searchMatchesFetchedLinkTitles() throws {
        let store = try makeStore()
        let item = ClipboardItem(content: "https://example.com/x", contentType: .url)
        store.add(item: item)
        store.setLinkTitle(id: item.id, title: "Apple Developer Documentation")

        #expect(store.search(query: "developer documentation").map(\.id) == [item.id])
    }

    @Test func fileItemRoundTripsCopiedFiles() throws {
        let files = [CopiedFile(name: "a.txt", path: "/tmp/a.txt", bookmark: nil),
                     CopiedFile(name: "b.png", path: "/tmp/b.png", bookmark: nil)]
        let data = try JSONEncoder().encode(files)
        let item = ClipboardItem(content: "a.txt, b.png", contentType: .file,
                                 fileInfoData: data)

        #expect(item.copiedFiles.map(\.name) == ["a.txt", "b.png"])
        #expect(item.contentType == .file)
    }

    @Test func richRepresentationsPersist() throws {
        let store = try makeStore()
        let rtf = Data("rtf-bytes".utf8)
        let html = Data("<b>hi</b>".utf8)
        let item = ClipboardItem(content: "hi", contentType: .plainText,
                                 rtfData: rtf, htmlData: html)
        store.add(item: item)

        let fetched = store.recentItems(limit: 1).first
        #expect(fetched?.rtfData == rtf)
        #expect(fetched?.htmlData == html)
    }
}
