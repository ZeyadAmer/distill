import Testing
import Foundation
import SwiftData
@testable import Hotstash

/// Reproduces "folder disappears after quitting": create a folder against a
/// real on-disk store, tear the container down, reopen a fresh container on the
/// same file, and assert the folder is still there. In-memory stores can't
/// catch a missing-schema / unsaved-context bug, so this uses a file URL.
struct FolderPersistenceTests {

    @Test func folderSurvivesContainerReopen() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folder-persist-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // First launch: create a folder, then drop the container (≈ quitting).
        do {
            let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: ClipboardItem.self, StoredTransform.self, Folder.self,
                configurations: config
            )
            let store = ClipboardStore(container: container)
            store.createFolder(name: "Work")
            #expect(store.folders.count == 1)
        }

        // Second launch: fresh container on the same file.
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ClipboardItem.self, StoredTransform.self, Folder.self,
            configurations: config
        )
        let reopened = ClipboardStore(container: container)
        #expect(reopened.folders.count == 1)
        #expect(reopened.folders.first?.name == "Work")
    }
}
