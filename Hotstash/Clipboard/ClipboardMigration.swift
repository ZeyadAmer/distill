import Foundation
import OSLog
import SwiftData

/// One-time migration of clipboard history from the legacy UserDefaults JSON
/// blob into SwiftData. Idempotent: guarded by a persisted flag and safe to
/// call on every launch.
@MainActor
enum ClipboardMigration {

    private static let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "ClipboardMigration")

    private enum Keys {
        static let legacyItems = "com.zeyadamer.hotstash.clipboardItems"
        static let legacyMaxItems = "com.zeyadamer.hotstash.maxItems"
        static let didMigrate = "com.zeyadamer.hotstash.didMigrateToSwiftData"
    }

    /// Runs migration if it has not already completed. Returns the number of
    /// items migrated (0 if already migrated or nothing to migrate).
    @discardableResult
    static func runIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> Int {
        guard !defaults.bool(forKey: Keys.didMigrate) else { return 0 }

        var migrated = 0
        if let data = defaults.data(forKey: Keys.legacyItems) {
            let legacy: [LegacyClipboardItem]
            do {
                legacy = try JSONDecoder().decode([LegacyClipboardItem].self, from: data)
            } catch {
                // Corrupt legacy blob: decoding is deterministic, so retrying is
                // pointless — mark migrated to stop looping, but keep the blob
                // in defaults so the data stays recoverable for support.
                logger.error("Clipboard migration decode failed, keeping legacy blob: \(error, privacy: .public)")
                defaults.set(true, forKey: Keys.didMigrate)
                return 0
            }
            // Preserve legacy pinned order by the sequence pins appear in the decoded array.
            var pinnedOrder = 0
            for old in legacy {
                let item = ClipboardItem(
                    id: old.id,
                    content: old.content,
                    contentType: old.contentType,
                    timestamp: old.timestamp,
                    isPinned: old.isPinned,
                    pinnedOrder: old.isPinned ? pinnedOrder : 0,
                    useCount: old.useCount,
                    imageData: old.imageData
                )
                if old.isPinned { pinnedOrder += 1 }
                context.insert(item)
                migrated += 1
            }
            do {
                try context.save()
            } catch {
                // Persisting failed (e.g. disk full, store not ready).
                // Leave legacy data + flag intact so migration retries next launch.
                logger.error("Clipboard migration save failed: \(error, privacy: .public)")
                return 0
            }
        }

        // Only reached when there was nothing to migrate, or the save succeeded.
        defaults.set(true, forKey: Keys.didMigrate)
        defaults.removeObject(forKey: Keys.legacyItems)
        defaults.removeObject(forKey: Keys.legacyMaxItems)
        return migrated
    }
}
