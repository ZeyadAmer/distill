import Foundation

// MARK: - ClipboardStore

/// In-memory clipboard history backed by UserDefaults for persistence.
///
/// All mutations must happen on the main actor so observers always see a
/// consistent snapshot.  The store enforces a configurable upper bound on
/// the total number of items; when the limit is reached the oldest
/// non-pinned item is evicted first.
@MainActor
final class ClipboardStore {

    // MARK: Singleton

    static let shared = ClipboardStore()

    // MARK: Constants

    private enum Keys {
        static let items    = "com.zeyadamer.hotstash.clipboardItems"
        static let maxItems = "com.zeyadamer.hotstash.maxItems"
    }

    /// Default upper limit — can be overridden via UserDefaults.
    private static let defaultMaxItems = 200

    // MARK: Public properties

    /// Full ordered list of clipboard items (pinned + recent, newest first).
    private(set) var items: [ClipboardItem] = []

    /// Pinned items only, in the order they were pinned (first in `items` array).
    var pinnedItems: [ClipboardItem] {
        items.filter { $0.isPinned }
    }

    /// Non-pinned items, sorted by timestamp descending.
    var recentItems: [ClipboardItem] {
        items
            .filter { !$0.isPinned }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Maximum number of items to retain.  Changing this value immediately
    /// re-enforces the limit and persists.
    var maxItems: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Keys.maxItems)
            return stored > 0 ? stored : Self.defaultMaxItems
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.maxItems)
            enforceLimit()
            persist()
        }
    }

    // MARK: Init

    private init() {
        load()
    }

    // MARK: - Mutations

    /// Prepends a new item and enforces the maximum limit.
    func add(item: ClipboardItem) {
        items.insert(item, at: 0)
        enforceLimit()
        persist()
    }

    /// Pins the item with the given id (no-op if already pinned or not found).
    func pin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isPinned else { return }
        items[index].isPinned = true
        persist()
    }

    /// Unpins the item with the given id (no-op if not pinned or not found).
    func unpin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].isPinned else { return }
        items[index].isPinned = false
        persist()
    }

    /// Removes the item with the given id entirely.
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// Removes all non-pinned items.
    func clearAll() {
        items.removeAll { !$0.isPinned }
        persist()
    }

    /// Moves an existing item to the front of the unpinned list without creating a duplicate.
    func moveToTop(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isPinned else { return }
        let item = items.remove(at: index)
        // Insert after any pinned items so it sits at the top of the recent section.
        let insertAt = items.firstIndex(where: { !$0.isPinned }) ?? items.endIndex
        items.insert(item, at: insertAt)
        persist()
    }

    /// Increments the use count for the item, recording that it was pasted.
    func recordUse(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].useCount += 1
        persist()
    }

    // MARK: - Search

    /// Returns items whose content contains `query` (case-insensitive).
    func search(query: String) -> [ClipboardItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return items
        }
        return items.filter {
            $0.content.range(of: query, options: .caseInsensitive) != nil
        }
    }

    // MARK: - Private helpers

    /// Drops the oldest non-pinned item(s) until the count is within the limit.
    private func enforceLimit() {
        let limit = maxItems
        guard items.count > limit else { return }

        // Build a list of non-pinned indices sorted oldest-first.
        let evictionCandidates = items
            .enumerated()
            .filter { !$0.element.isPinned }
            .sorted { $0.element.timestamp < $1.element.timestamp }

        var excess = items.count - limit
        var indicesToRemove: [Int] = []

        for candidate in evictionCandidates {
            guard excess > 0 else { break }
            indicesToRemove.append(candidate.offset)
            excess -= 1
        }

        // Remove in reverse order to keep indices valid.
        for index in indicesToRemove.sorted().reversed() {
            items.remove(at: index)
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Keys.items)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.items),
            let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else {
            items = []
            return
        }
        items = decoded
    }
}
