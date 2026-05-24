import Foundation
import UIKit

// Ordered queue of text items for sequential pasting.
@MainActor
final class MultiPasteStore: ObservableObject {

    static let shared = MultiPasteStore()

    @Published private(set) var queue: [MultiPasteItem] = []
    @Published private(set) var currentIndex: Int = 0

    private init() { load() }

    var currentItem: MultiPasteItem? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var isFinished: Bool { currentIndex >= queue.count }

    // MARK: - Queue management

    func enqueue(text: String) {
        let item = MultiPasteItem(text: text)
        queue.append(item)
        persist()
    }

    func enqueueAll(texts: [String]) {
        texts.forEach { queue.append(MultiPasteItem(text: $0)) }
        persist()
    }

    func remove(id: UUID) {
        if let i = queue.firstIndex(where: { $0.id == id }), i < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        }
        queue.removeAll { $0.id == id }
        persist()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        queue.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    func clearAll() {
        queue.removeAll()
        currentIndex = 0
        persist()
    }

    // MARK: - Pasting

    /// Copies current item to clipboard and advances to next.
    @discardableResult
    func pasteNext() -> String? {
        guard let item = currentItem else { return nil }
        UIPasteboard.general.string = item.text
        currentIndex += 1
        return item.text
    }

    func reset() {
        currentIndex = 0
    }

    /// Joins all queued items with the given separator and copies to clipboard.
    @discardableResult
    func copyAll(separator: String) -> String {
        let joined = queue.map { $0.text }.joined(separator: separator)
        UIPasteboard.general.string = joined
        return joined
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        SharedDefaults.store.set(data, forKey: SharedDefaults.Keys.multiPasteQueue)
    }

    private func load() {
        guard
            let data    = SharedDefaults.store.data(forKey: SharedDefaults.Keys.multiPasteQueue),
            let decoded = try? JSONDecoder().decode([MultiPasteItem].self, from: data)
        else { return }
        queue = decoded
    }
}

struct MultiPasteItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}
