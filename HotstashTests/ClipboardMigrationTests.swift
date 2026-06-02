import Testing
import Foundation
import SwiftData
@testable import Hotstash

@MainActor
struct ClipboardMigrationTests {

    // Retain the container for the lifetime of the test. A ModelContext does
    // not keep its ModelContainer alive; letting the container deallocate
    // leaves the context pointing at a freed in-memory store, which traps in
    // SwiftData on the next save/fetch.
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainer.hotstashInMemory()
        context = container.mainContext
    }

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "migration-test-\(UUID().uuidString)")!
        return suite
    }

    @Test func migratesLegacyItemsAndClearsKeys() throws {
        let defaults = makeDefaults()
        let legacy = [
            LegacyClipboardItem(id: UUID(), content: "one", contentType: .plainText,
                                timestamp: .now, isPinned: true, useCount: 3, imageData: nil),
            LegacyClipboardItem(id: UUID(), content: "two", contentType: .url,
                                timestamp: .now, isPinned: false, useCount: 0, imageData: nil),
        ]
        let data = try JSONEncoder().encode(legacy)
        defaults.set(data, forKey: "com.zeyadamer.hotstash.clipboardItems")

        let count = ClipboardMigration.runIfNeeded(context: context, defaults: defaults)
        #expect(count == 2)

        let stored = try context.fetch(FetchDescriptor<ClipboardItem>())
        #expect(stored.count == 2)
        #expect(stored.contains { $0.content == "one" && $0.isPinned && $0.useCount == 3 })
        #expect(defaults.bool(forKey: "com.zeyadamer.hotstash.didMigrateToSwiftData"))
        #expect(defaults.data(forKey: "com.zeyadamer.hotstash.clipboardItems") == nil)
    }

    @Test func isIdempotent() throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "com.zeyadamer.hotstash.didMigrateToSwiftData")
        let count = ClipboardMigration.runIfNeeded(context: context, defaults: defaults)
        #expect(count == 0)
        #expect(try context.fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }
}
