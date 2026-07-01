import Foundation
import SwiftData

// MARK: - Folder

/// A user-created collection that appears as its own tab beside Recents and
/// Pinned. Items assigned to a folder (`ClipboardItem.folderID`) are kept out
/// of Recents and protected from history/image eviction, so a folder is durable
/// storage — not just a filter.
///
/// CloudKit constraints (matches `ClipboardItem`): every stored property has a
/// default value and there are no unique constraints. Uniqueness by `id` is
/// enforced in `ClipboardStore`.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    /// Stable left-to-right ordering of folder tabs (lower = further left).
    var order: Int = 0
    var timestamp: Date = Date.now

    init(id: UUID = UUID(), name: String, order: Int = 0, timestamp: Date = .now) {
        self.id = id
        self.name = name
        self.order = order
        self.timestamp = timestamp
    }
}
