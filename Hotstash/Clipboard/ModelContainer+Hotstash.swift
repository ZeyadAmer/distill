import Foundation
import SwiftData

extension ModelContainer {

    /// Production container: local SwiftData store mirrored to the user's
    /// private CloudKit database for cross-Mac sync and backup.
    static let hotstashShared: ModelContainer = {
        var cloud = ModelConfiguration.CloudKitDatabase.private("iCloud.com.zeyadamer.hotstash")
        #if DEBUG
        // Unsigned local builds have no iCloud entitlement and CloudKit traps
        // (not throws) on setup. Launch with `-debug.localStore YES` to run them.
        if UserDefaults.standard.bool(forKey: "debug.localStore") { cloud = .none }
        #endif
        let config = ModelConfiguration("Hotstash", cloudKitDatabase: cloud)
        do {
            return try ModelContainer(for: ClipboardItem.self, StoredTransform.self, Folder.self, configurations: config)
        } catch {
            // CloudKit store failed — fall back to a local-only store so the app
            // still launches without sync.
            let local = ModelConfiguration("Hotstash", cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: ClipboardItem.self, StoredTransform.self, Folder.self, configurations: local) {
                return container
            }
            // Local store also unopenable (disk full / corrupt store after a bad
            // migration). Force-trying here would crash on every launch forever,
            // locking the user out. Fall back to an in-memory store: the app
            // launches and works for this session instead of crash-looping.
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: ClipboardItem.self, StoredTransform.self, Folder.self, configurations: memory)
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
