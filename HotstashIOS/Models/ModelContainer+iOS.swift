import Foundation
import SwiftData

// MARK: - ModelContainer (iOS)

/// iOS counterparts of `ModelContainer.hotstashShared` (see
/// Hotstash/Clipboard/ModelContainer+Hotstash.swift). Same schema
/// (`ClipboardItem`, `StoredTransform`) and the same private CloudKit
/// database, so records sync 1:1 with the Mac app. The store lives in the
/// app group so extensions can open the same file.
extension ModelContainer {

    private static let storeName = "Hotstash"
    private static let cloudKitContainerID = "iCloud.com.zeyadamer.hotstash"

    /// Main-app container: app-group store mirrored to the user's private
    /// CloudKit database.
    static let hotstashIOS: ModelContainer = {
        let config = ModelConfiguration(
            storeName,
            groupContainer: .identifier(SharedDefaults.suiteName),
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        do {
            return try ModelContainer(for: ClipboardItem.self, StoredTransform.self, configurations: config)
        } catch {
            // A failed store is unrecoverable for a clipboard app; fall back to
            // a local-only store so the app still launches without sync.
            return ModelContainer.hotstashIOSLocal()
        }
    }()

    /// Platform-neutral default used by shared code (`MarketplaceLibrary`).
    static var hotstashDefault: ModelContainer { hotstashIOS }

    /// Extension container (share extension): opens the same app-group store
    /// WITHOUT CloudKit mirroring. Changes are recorded in persistent history
    /// and exported by the main app the next time it runs.
    static let hotstashIOSExtension: ModelContainer = hotstashIOSLocal()

    /// Local-only container over the shared app-group store.
    private static func hotstashIOSLocal() -> ModelContainer {
        let local = ModelConfiguration(
            storeName,
            groupContainer: .identifier(SharedDefaults.suiteName),
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: ClipboardItem.self, StoredTransform.self, configurations: local)
        } catch {
            // Last resort: in-memory store so the process never crashes at launch.
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: ClipboardItem.self, StoredTransform.self, configurations: memory)
        }
    }
}
