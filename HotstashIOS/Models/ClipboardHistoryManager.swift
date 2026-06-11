import Foundation
import CoreData
import SwiftData
import UIKit

// MARK: - ClipboardHistoryManager

/// Clipboard history backed by the shared SwiftData store (app group +
/// private CloudKit database), so items copied on the Mac appear here too.
///
/// Responsibilities:
/// - Reads the system clipboard when the app foregrounds and persists new items.
/// - Publishes pinned + recent items for the UI, refreshing when CloudKit
///   imports land (`NSPersistentStoreRemoteChange`).
/// - Mirrors the latest text items into the app-group UserDefaults so the
///   keyboard extension can show them without opening the store.
@MainActor
final class ClipboardHistoryManager: ObservableObject {

    static let shared = ClipboardHistoryManager()

    // MARK: Constants

    private static let recentFetchLimit = 500
    private static let searchFetchLimit = 500
    private static let remoteRefreshDebounce: UInt64 = 300_000_000 // 300 ms
    private let changeCountKey = "hotstash.lastClipboardChangeCount"

    // MARK: State

    /// Pinned items first (by `pinnedOrder`), then recents newest-first.
    @Published private(set) var items: [ClipboardItem] = []

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var pendingRefresh: Task<Void, Never>?

    // MARK: Init

    init(container: ModelContainer = .hotstashIOS) {
        self.container = container

        // Seed with the current change count so the first foreground after
        // install doesn't trigger the paste permission dialog for pre-existing
        // clipboard content.
        if UserDefaults.standard.object(forKey: changeCountKey) == nil {
            UserDefaults.standard.set(UIPasteboard.general.changeCount, forKey: changeCountKey)
        }

        refresh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        // Posted when CloudKit imports (or another process) change the store.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChangeRemotely),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
    }

    // MARK: - Clipboard polling

    private var lastSeenChangeCount: Int {
        get { UserDefaults.standard.object(forKey: changeCountKey) as? Int ?? UIPasteboard.general.changeCount }
        set { UserDefaults.standard.set(newValue, forKey: changeCountKey) }
    }

    @objc private func appDidBecomeActive() {
        checkClipboard()
        refresh()
    }

    func checkClipboard() {
        importPendingFromKeyboard()

        let board = UIPasteboard.general
        let current = board.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current

        guard let text = board.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        // Same content already in history → just bump it to the top.
        if let existing = existingUnpinned(content: text) {
            existing.timestamp = .now
            save()
            refresh()
            return
        }
        guard existingPinned(content: text) == nil else { return }

        add(item: ClipboardItem(content: text, contentType: ContentDetector.detect(text)))
    }

    /// Turns texts captured by the keyboard extension into real history items
    /// (which then sync to the Mac via CloudKit).
    private func importPendingFromKeyboard() {
        let pending = PendingImports.drain()
        guard !pending.isEmpty else { return }
        for text in pending {
            if let existing = existingUnpinned(content: text) {
                existing.timestamp = .now
                continue
            }
            if existingPinned(content: text) != nil { continue }
            context.insert(ClipboardItem(content: text, contentType: ContentDetector.detect(text)))
        }
        save()
        refresh()
    }

    // MARK: - Mutations

    func add(item: ClipboardItem) {
        context.insert(item)
        save()
        refresh()
    }

    func remove(id: UUID) {
        guard let item = item(id: id) else { return }
        context.delete(item)
        save()
        refresh()
    }

    func pin(id: UUID) {
        guard let item = item(id: id), !item.isPinned else { return }
        item.isPinned = true
        item.pinnedOrder = (pinnedItems.map(\.pinnedOrder).max() ?? -1) + 1
        save()
        refresh()
    }

    func unpin(id: UUID) {
        guard let item = item(id: id), item.isPinned else { return }
        item.isPinned = false
        save()
        refresh()
    }

    /// Deletes all non-pinned items.
    func clearUnpinned() {
        do {
            try context.delete(model: ClipboardItem.self, where: #Predicate { !$0.isPinned })
        } catch {
            print("[ClipboardHistoryManager] clearUnpinned failed: \(error.localizedDescription)")
        }
        save()
        refresh()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        if item.hasImage, let data = item.imageData, let image = UIImage(data: data) {
            UIPasteboard.general.image = image
        } else {
            UIPasteboard.general.string = item.content
        }
        lastSeenChangeCount = UIPasteboard.general.changeCount
        item.useCount += 1
        save()
    }

    // MARK: - Search

    /// Case-insensitive substring match over content, OCR text, and link titles.
    func search(query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate {
                $0.content.localizedStandardContains(trimmed)
                || $0.ocrText.localizedStandardContains(trimmed)
                || $0.linkTitle.localizedStandardContains(trimmed)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = Self.searchFetchLimit
        return fetch(descriptor)
    }

    // MARK: - Refresh

    /// Re-fetches the published list and updates the keyboard mirror.
    func refresh() {
        var recent = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recent.fetchLimit = Self.recentFetchLimit
        items = pinnedItems + fetch(recent)
        mirrorToKeyboard()
    }

    @objc nonisolated private func storeDidChangeRemotely(_ note: Notification) {
        Task { @MainActor [weak self] in self?.scheduleRefresh() }
    }

    /// Debounces bursts of remote-change notifications during CloudKit imports.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.remoteRefreshDebounce)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Keyboard mirror

    /// Mirrors the latest text items into the app group for the keyboard
    /// extension (its only data source — see `KeyboardClipsMirror`).
    private func mirrorToKeyboard() {
        let clips = items
            .filter { !$0.hasImage && $0.contentType != .file && !$0.content.isEmpty }
            .prefix(KeyboardClipsMirror.maxClips)
            .map { KeyboardClip(id: $0.id, content: $0.content, contentTypeRaw: $0.contentTypeRaw, isPinned: $0.isPinned) }
        KeyboardClipsMirror.write(Array(clips))
    }

    // MARK: - Private helpers

    private var pinnedItems: [ClipboardItem] {
        fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.pinnedOrder), SortDescriptor(\.timestamp, order: .reverse)]
        ))
    }

    private func existingUnpinned(content: String) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.content == content }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func existingPinned(content: String) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned && $0.content == content }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

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
            print("[ClipboardHistoryManager] SwiftData save failed: \(error.localizedDescription)")
        }
    }
}
