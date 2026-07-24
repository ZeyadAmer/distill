import Testing
import Foundation
import SwiftData
@testable import Hotstash

@MainActor
struct ClipboardStoreTests {

    private func makeStore() throws -> ClipboardStore {
        let container = try ModelContainer.hotstashInMemory()
        return ClipboardStore(container: container)
    }

    @Test func addInsertsNewestFirst() throws {
        let store = try makeStore()
        store.add(item: ClipboardItem(content: "first", contentType: .plainText,
                                      timestamp: Date(timeIntervalSince1970: 1)))
        store.add(item: ClipboardItem(content: "second", contentType: .plainText,
                                      timestamp: Date(timeIntervalSince1970: 2)))
        let page = store.recentItems(limit: 10)
        #expect(page.map(\.content) == ["second", "first"])
    }

    @Test func pinAndUnpin() throws {
        let store = try makeStore()
        let item = ClipboardItem(content: "x", contentType: .plainText)
        store.add(item: item)
        store.pin(id: item.id)
        #expect(store.pinnedItems.map(\.id) == [item.id])
        #expect(store.recentItems(limit: 10).isEmpty)
        store.unpin(id: item.id)
        #expect(store.pinnedItems.isEmpty)
        #expect(store.recentItems(limit: 10).count == 1)
    }

    @Test func removeAndClearAllKeepsPinned() throws {
        let store = try makeStore()
        let a = ClipboardItem(content: "a", contentType: .plainText)
        let b = ClipboardItem(content: "b", contentType: .plainText)
        store.add(item: a); store.add(item: b)
        store.pin(id: a.id)
        store.clearAll()
        #expect(store.recentItems(limit: 10).isEmpty)
        #expect(store.pinnedItems.map(\.id) == [a.id])
        store.remove(id: a.id)
        #expect(store.pinnedItems.isEmpty)
    }

    @Test func searchMatchesCaseInsensitive() throws {
        let store = try makeStore()
        store.add(item: ClipboardItem(content: "Hello World", contentType: .plainText))
        store.add(item: ClipboardItem(content: "goodbye", contentType: .plainText))
        #expect(store.search(query: "hello").count == 1)
        #expect(store.search(query: "O").count == 2)
    }

    @Test func searchRanksLabelMatchesFirst() throws {
        let store = try makeStore()
        let byContent = ClipboardItem(content: "deploy the app", contentType: .plainText,
                                      timestamp: Date(timeIntervalSince1970: 2))
        let byLabel = ClipboardItem(content: "xyz", contentType: .plainText,
                                    timestamp: Date(timeIntervalSince1970: 1))
        store.add(item: byContent); store.add(item: byLabel)
        store.setLabel(id: byLabel.id, label: "deploy")
        #expect(store.search(query: "deploy").map(\.id) == [byLabel.id, byContent.id])
    }

    @Test func searchReflectsChangesAfterIndexBuilt() throws {
        let store = try makeStore()
        store.add(item: ClipboardItem(content: "alpha", contentType: .plainText))
        #expect(store.search(query: "beta").isEmpty)  // builds the index
        store.add(item: ClipboardItem(content: "beta", contentType: .plainText))
        #expect(store.search(query: "beta").count == 1)
    }

    @Test func searchToleratesDuplicateIDsFromCloudKitSync() throws {
        let store = try makeStore()
        // CloudKit merges can produce two rows with the same id — the model
        // has no unique constraint. Search must not trap and must return
        // the item once.
        let sharedID = UUID()
        store.add(item: ClipboardItem(id: sharedID, content: "duplicated row", contentType: .plainText))
        store.add(item: ClipboardItem(id: sharedID, content: "duplicated row", contentType: .plainText))
        #expect(store.items.count == 2)  // both rows really exist
        let results = store.search(query: "duplicated")
        #expect(results.count == 1)
        #expect(results.first?.id == sharedID)
    }

    @Test func existingUnpinnedFindsExactMatch() throws {
        let store = try makeStore()
        store.add(item: ClipboardItem(content: "needle", contentType: .plainText))
        store.add(item: ClipboardItem(content: "needle in haystack", contentType: .plainText))
        let found = store.existingUnpinned(content: "needle")
        #expect(found?.content == "needle")
        #expect(store.existingUnpinned(content: "missing") == nil)
    }

    @Test func reorderPinnedByOrder() throws {
        let store = try makeStore()
        let a = ClipboardItem(content: "a", contentType: .plainText)
        let b = ClipboardItem(content: "b", contentType: .plainText)
        let c = ClipboardItem(content: "c", contentType: .plainText)
        for i in [a, b, c] { store.add(item: i); store.pin(id: i.id) }
        // pinned order is a, b, c. Move index 0 -> 2.
        store.reorderPinned(from: 0, to: 2)
        #expect(store.pinnedItems.map(\.content) == ["b", "c", "a"])
    }

    @Test func recordUseIncrements() throws {
        let store = try makeStore()
        let item = ClipboardItem(content: "x", contentType: .plainText)
        store.add(item: item)
        store.recordUse(id: item.id)
        store.recordUse(id: item.id)
        #expect(store.recentItems(limit: 1).first?.useCount == 2)
    }

    @Test func imageBudgetEvictsOldestNonPinned() throws {
        let store = try makeStore()
        // Add maxImageCount + 5 image items; the oldest 5 should be evicted by count.
        let total = ClipboardStore.maxImageCount + 5
        for i in 0..<total {
            store.add(item: ClipboardItem(
                content: "[Image]", contentType: .image,
                timestamp: Date(timeIntervalSince1970: TimeInterval(i)),
                imageData: Data([UInt8(i % 255)])
            ))
        }
        let imageCount = store.recentItems(limit: total).filter { $0.contentType == .image }.count
        #expect(imageCount == ClipboardStore.maxImageCount)
    }
}
