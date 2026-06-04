import Foundation
import OSLog
import SwiftData

// MARK: - ClipboardStore

/// Clipboard history backed by SwiftData (and CloudKit via the shared container).
///
/// Text history is unbounded. Image bodies are capped by a rolling budget
/// (`maxImageCount` / `maxImageBytes`); the oldest non-pinned image items are
/// evicted first. Pinned items are never auto-evicted.
@MainActor
final class ClipboardStore {

    // MARK: Singleton / init

    static let shared = ClipboardStore()

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "ClipboardStore")

    /// Production uses the shared CloudKit container; tests inject in-memory.
    init(container: ModelContainer = .hotstashShared) {
        self.container = container
    }

    /// Context used by one-time migration at launch.
    var modelContextForMigration: ModelContext { context }

    // MARK: History limit

    /// Maximum number of non-pinned items to retain. `nil` means unlimited.
    /// Stored in UserDefaults as a positive Int; 0 → unlimited.
    var maxHistoryItems: Int? {
        get {
            let v = UserDefaults.standard.integer(forKey: "historyLimit")
            return v > 0 ? v : nil
        }
        set {
            UserDefaults.standard.set(newValue ?? 0, forKey: "historyLimit")
        }
    }

    // MARK: Image budget constants

    /// Keep at most this many image items.
    static let maxImageCount = 200
    /// Keep image bodies under this total byte budget (~50MB).
    static let maxImageBytes = 50 * 1024 * 1024

    // MARK: Reads

    /// All items, newest first. Use sparingly — prefer `recentItems(limit:offset:)`.
    var items: [ClipboardItem] {
        fetch(FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))
    }

    /// Pinned items, ordered by `pinnedOrder` then recency.
    var pinnedItems: [ClipboardItem] {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.pinnedOrder), SortDescriptor(\.timestamp, order: .reverse)]
        )
        return fetch(descriptor)
    }

    /// A page of non-pinned items, newest first.
    func recentItems(limit: Int, offset: Int = 0) -> [ClipboardItem] {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return fetch(descriptor)
    }

    /// Count of non-pinned items.
    var recentCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }
        ))) ?? 0
    }

    // MARK: Search

    /// Case-insensitive substring match across the full history (capped for UI).
    func search(query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.content.localizedStandardContains(trimmed) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return fetch(descriptor)
    }

    /// Returns the existing non-pinned item with exactly this content, if any.
    func existingUnpinned(content: String) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.content == content }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// Returns the existing pinned item with exactly this content, if any.
    func existingPinned(content: String) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned && $0.content == content }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    // MARK: Mutations

    func add(item: ClipboardItem) {
        context.insert(item)
        save()
        if item.hasImage { enforceImageBudget() }
        enforceHistoryLimit()
    }

    func pin(id: UUID) {
        guard let item = item(id: id), !item.isPinned else { return }
        item.isPinned = true
        item.pinnedOrder = (pinnedItems.map(\.pinnedOrder).max() ?? -1) + 1
        save()
    }

    func unpin(id: UUID) {
        guard let item = item(id: id), item.isPinned else { return }
        item.isPinned = false
        save()
    }

    func remove(id: UUID) {
        guard let item = item(id: id) else { return }
        context.delete(item)
        save()
    }

    /// Deletes all non-pinned items.
    func clearAll() {
        do {
            try context.delete(model: ClipboardItem.self, where: #Predicate { !$0.isPinned })
        } catch {
            logger.error("clearAll delete failed: \(error, privacy: .public)")
        }
        save()
    }

    /// Reorders pinned items by reassigning `pinnedOrder`.
    func reorderPinned(from source: Int, to destination: Int) {
        var pinned = pinnedItems
        guard source >= 0, source < pinned.count,
              destination >= 0, destination <= pinned.count, source != destination
        else { return }
        let moved = pinned.remove(at: source)
        let insertAt = min(destination, pinned.count)
        pinned.insert(moved, at: insertAt)
        for (index, item) in pinned.enumerated() { item.pinnedOrder = index }
        save()
    }

    /// Bumps a non-pinned item to the top of the recent list (by recency).
    /// Note: mutates timestamp, so this change propagates via CloudKit (last-writer-wins on merge).
    func moveToTop(id: UUID) {
        guard let item = item(id: id), !item.isPinned else { return }
        item.timestamp = .now
        save()
    }

    func recordUse(id: UUID) {
        guard let item = item(id: id) else { return }
        item.useCount += 1
        save()
    }

    // MARK: Image budget

    /// Evicts oldest non-pinned image items until both the count and byte
    /// budgets are satisfied. Pinned images are always retained.
    func enforceImageBudget() {
        var imageItems = fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.hasImage },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]  // newest first
        ))
        var totalBytes = imageItems.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        var changed = false
        // Evict from the oldest end while over budget.
        while (imageItems.count > Self.maxImageCount || totalBytes > Self.maxImageBytes),
              let oldest = imageItems.popLast() {
            totalBytes -= (oldest.imageData?.count ?? 0)
            context.delete(oldest)
            changed = true
        }
        if changed { save() }
    }

    /// Deletes the oldest non-pinned items when the count exceeds `maxHistoryItems`.
    func enforceHistoryLimit() {
        guard let limit = maxHistoryItems else { return }
        let excess = recentCount - limit
        guard excess > 0 else { return }
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.timestamp)]   // oldest first
        )
        descriptor.fetchLimit = excess
        let toDelete = fetch(descriptor)
        toDelete.forEach { context.delete($0) }
        if !toDelete.isEmpty { save() }
    }

    // MARK: Private helpers

    private func item(id: UUID) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func fetch(_ descriptor: FetchDescriptor<ClipboardItem>) -> [ClipboardItem] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("SwiftData save failed: \(error, privacy: .public)")
        }
    }
}
