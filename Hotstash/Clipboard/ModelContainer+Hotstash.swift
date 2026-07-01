import Foundation
import SwiftData

extension ModelContainer {

    /// Production container: local SwiftData store mirrored to the user's
    /// private CloudKit database for cross-Mac sync and backup.
    static let hotstashShared: ModelContainer = {
        let config = ModelConfiguration(
            "Hotstash",
            cloudKitDatabase: .private("iCloud.com.zeyadamer.hotstash")
        )
        do {
            return try ModelContainer(for: ClipboardItem.self, StoredTransform.self, Folder.self, configurations: config)
        } catch {
            // A failed store is unrecoverable for a clipboard app; fall back to
            // a local-only store so the app still launches without sync.
            let local = ModelConfiguration("Hotstash", cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: ClipboardItem.self, StoredTransform.self, Folder.self, configurations: local)
        }
    }()

    /// Platform-neutral default used by shared code (`MarketplaceLibrary`).
    /// iOS defines its own counterpart in ModelContainer+iOS.swift.
    static var hotstashDefault: ModelContainer { hotstashShared }

    /// In-memory container for unit tests.
    static func hotstashInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipboardItem.self, StoredTransform.self, Folder.self, configurations: config)
    }
}
