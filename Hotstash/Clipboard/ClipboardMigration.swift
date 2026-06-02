import Foundation
import SwiftData

/// One-time migration of clipboard history from the legacy UserDefaults JSON
/// blob into SwiftData. Idempotent: guarded by a persisted flag and safe to
/// call on every launch.
@MainActor
enum ClipboardMigration {

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
        if let data = defaults.data(forKey: Keys.legacyItems),
           let legacy = try? JSONDecoder().decode([LegacyClipboardItem].self, from: data) {
            for old in legacy {
                let item = ClipboardItem(
                    id: old.id,
                    content: old.content,
                    contentType: old.contentType,
                    timestamp: old.timestamp,
                    isPinned: old.isPinned,
                    useCount: old.useCount,
                    imageData: old.imageData
                )
                context.insert(item)
                migrated += 1
            }
            try? context.save()
        }

        defaults.set(true, forKey: Keys.didMigrate)
        defaults.removeObject(forKey: Keys.legacyItems)
        defaults.removeObject(forKey: Keys.legacyMaxItems)
        return migrated
    }
}
