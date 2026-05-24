import Foundation
import UIKit

// Reads clipboard when app foregrounds, stores up to 50 items in App Group UserDefaults.
@MainActor
final class ClipboardHistoryManager: ObservableObject {

    static let shared = ClipboardHistoryManager()

    private let maxItems = 50
    private let changeCountKey = "hotstash.lastClipboardChangeCount"

    private var lastSeenChangeCount: Int {
        get { UserDefaults.standard.object(forKey: changeCountKey) as? Int ?? UIPasteboard.general.changeCount }
        set { UserDefaults.standard.set(newValue, forKey: changeCountKey) }
    }

    @Published private(set) var items: [ClipboardItem] = []

    private init() {
        load()
        // Seed with current count so the first foreground after install
        // doesn't trigger the paste permission dialog for pre-existing content.
        if UserDefaults.standard.object(forKey: changeCountKey) == nil {
            UserDefaults.standard.set(UIPasteboard.general.changeCount, forKey: changeCountKey)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - Clipboard polling

    @objc private func appDidBecomeActive() {
        checkClipboard()
    }

    func checkClipboard() {
        let board = UIPasteboard.general
        let current = board.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current

        guard let text = board.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Skip if identical to most recent item
        if let top = items.first(where: { !$0.isPinned }), top.content == text { return }

        let item = ClipboardItem(
            content: text,
            contentType: ContentDetector.detect(text)
        )
        add(item: item)
    }

    // MARK: - Mutations

    func add(item: ClipboardItem) {
        items.insert(item, at: 0)
        enforceLimit()
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func pin(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isPinned = true
        persist()
    }

    func unpin(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isPinned = false
        persist()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        persist()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        UIPasteboard.general.string = item.content
        lastSeenChangeCount = UIPasteboard.general.changeCount
        // Increment use count
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i].useCount += 1
            persist()
        }
    }

    // MARK: - Search

    func search(query: String) -> [ClipboardItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.filter {
            $0.content.range(of: query, options: .caseInsensitive) != nil
        }
    }

    // MARK: - Private

    private func enforceLimit() {
        var nonPinned = items.filter { !$0.isPinned }.sorted { $0.timestamp > $1.timestamp }
        let pinned    = items.filter { $0.isPinned }
        if nonPinned.count > maxItems {
            nonPinned = Array(nonPinned.prefix(maxItems))
        }
        items = pinned + nonPinned
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        SharedDefaults.store.set(data, forKey: SharedDefaults.Keys.clipboardHistory)
    }

    private func load() {
        guard
            let data    = SharedDefaults.store.data(forKey: SharedDefaults.Keys.clipboardHistory),
            let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        items = decoded
    }
}
