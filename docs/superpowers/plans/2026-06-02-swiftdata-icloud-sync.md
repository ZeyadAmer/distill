# SwiftData Storage + Unlimited History + iCloud Sync — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace UserDefaults clipboard history with a SwiftData store, remove the text-history cap (unlimited), and mirror history to the user's private CloudKit database for cross-Mac sync and backup.

**Architecture:** `ClipboardItem` becomes a SwiftData `@Model`. `ClipboardStore` keeps its public API but is reimplemented as a `@MainActor` facade over a `ModelContext`. A shared `ModelContainer` enables CloudKit private-DB mirroring. The AppKit panel pages over the store instead of loading the whole array. A one-time migration moves the legacy UserDefaults blob into SwiftData. `ClipboardMonitor` gains a concealed/transient filter so sensitive copies never enter history.

**Tech Stack:** Swift 5.9, SwiftData, CloudKit, AppKit, Swift Testing, xcodegen.

Spec: `docs/superpowers/specs/2026-06-02-swiftdata-icloud-sync-design.md`

---

## File Map

**Create:**
- `Hotstash/Clipboard/ModelContainer+Hotstash.swift` — shared CloudKit-backed container factory.
- `Hotstash/Clipboard/LegacyClipboardItem.swift` — Codable mirror of the old struct, for migration only.
- `Hotstash/Clipboard/ClipboardMigration.swift` — one-time UserDefaults → SwiftData migration.
- `HotstashTests/ClipboardStoreTests.swift` — store unit tests.
- `HotstashTests/ClipboardMigrationTests.swift` — migration unit tests.

**Modify:**
- `project.yml` — macOS 14, drop iOS targets, add iCloud entitlement, add test target.
- `Hotstash/Resources/Hotstash.entitlements` — iCloud + network.client.
- `Hotstash/Clipboard/ClipboardItem.swift` — struct → `@Model` class (+ keep ContentType UI extensions).
- `Hotstash/Clipboard/ClipboardStore.swift` — facade over `ModelContext`.
- `Hotstash/Clipboard/ClipboardMonitor.swift` — concealed/transient filter; predicate-based de-dup.
- `Hotstash/App/AppDelegate.swift` — run migration before monitor starts.
- `Hotstash/UI/Panel/ClipboardPanelVC.swift` — paging + load-more; tab-aware fetch.
- `Hotstash/UI/Settings/GeneralSettingsView.swift` — remove text history-limit picker.
- `Hotstash/UI/MultiPaste/MultiPastePanel.swift` — use `recentItems(limit:offset:)`.

---

## Task 0: Project config — macOS 14, drop iOS targets, iCloud, test target

**Files:**
- Modify: `project.yml`
- Modify: `Hotstash/Resources/Hotstash.entitlements`

Not TDD (build config). Verify by regenerating and building.

- [ ] **Step 1: Bump macOS target and remove iOS targets in `project.yml`**

In `options.deploymentTarget`, set `macOS: "14.0"` and delete the `iOS: "16.0"` line.
In `settings.base`, set `MACOSX_DEPLOYMENT_TARGET: "14.0"`.
In the `Hotstash` target's `settings.base`, set `deploymentTarget: "14.0"` and `MACOSX_DEPLOYMENT_TARGET: "14.0"`.
Delete the entire `HotstashIOS`, `HotstashShare`, `HotstashControls` target blocks.
Delete the `HotstashIOS` and `HotstashControls-History` scheme blocks. Keep only the `Hotstash` scheme.

Add the iCloud entitlement to the `Hotstash` target's `entitlements.properties`:

```yaml
    entitlements:
      path: Hotstash/Resources/Hotstash.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.automation.apple-events: true
        com.apple.security.network.client: true
        com.apple.developer.icloud-container-identifiers:
          - iCloud.com.zeyadamer.hotstash
        com.apple.developer.icloud-services:
          - CloudKit
        com.apple.developer.ubiquity-kvstore-identifier: $(TeamIdentifierPrefix)com.zeyadamer.hotstash
```

- [ ] **Step 2: Add a unit-test target to `project.yml`**

Add under `targets:` (sibling of `Hotstash`):

```yaml
  HotstashTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: HotstashTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.zeyadamer.hotstash.tests
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        DEVELOPMENT_TEAM: 4PMSUCCX7P
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Hotstash
```

Add a test scheme under `schemes.Hotstash`:

```yaml
  Hotstash:
    build:
      targets:
        Hotstash: all
        HotstashTests: [test]
    test:
      targets:
        - HotstashTests
    run:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 3: Make app source compilable into the test target**

The test target depends on `Hotstash` but Swift unit tests need access to internal types. Add `@testable import Hotstash` in test files (Task 7+). Ensure `Hotstash` target has `ENABLE_TESTABILITY: YES` for Debug. In `project.yml` under `Hotstash` `configs.Debug`, add:

```yaml
        Debug:
          SWIFT_OPTIMIZATION_LEVEL: "-Onone"
          DEBUG_INFORMATION_FORMAT: dwarf
          ONLY_ACTIVE_ARCH: YES
          ENABLE_TESTABILITY: YES
```

- [ ] **Step 4: Create the test source folder so xcodegen finds it**

```bash
mkdir -p HotstashTests
printf 'import Testing\n@testable import Hotstash\n\n@Test func smoke() { #expect(true) }\n' > HotstashTests/SmokeTests.swift
```

- [ ] **Step 5: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' build 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`. (App still uses the old struct store — fine, this task only changes config.)

- [ ] **Step 6: Run the smoke test**

```bash
xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' test 2>&1 | tail -20
```
Expected: test `smoke` passes.

- [ ] **Step 7: Commit**

```bash
git add project.yml Hotstash/Resources/Hotstash.entitlements HotstashTests/SmokeTests.swift
git commit -m "chore: target macOS 14, drop iOS targets, add iCloud entitlement + test target"
```

---

## Task 1: Convert `ClipboardItem` to a SwiftData `@Model`

**Files:**
- Modify: `Hotstash/Clipboard/ClipboardItem.swift`

The `ContentType` UI extensions (`displayName`, `badgeColor`) at the top of the file stay unchanged. Only the `struct ClipboardItem` definition (lines ~34-77) is replaced.

- [ ] **Step 1: Replace the struct with an `@Model` class**

First, add `import SwiftData` to the top of the file alongside the existing `import AppKit` / `import Foundation`.

Then replace the `// MARK: - ClipboardItem` section and the `struct ClipboardItem { ... }` with:

```swift
// MARK: - ClipboardItem

/// A single entry in the clipboard history, persisted by SwiftData and
/// mirrored to the user's private CloudKit database.
///
/// CloudKit constraints: every stored property has a default value and there
/// are no unique constraints. Uniqueness by `id` is enforced in `ClipboardStore`.
@Model
final class ClipboardItem {
    var id: UUID = UUID()
    var content: String = ""
    var contentTypeRaw: String = ContentType.plainText.rawValue
    var timestamp: Date = Date.now
    var isPinned: Bool = false
    /// Stable ordering among pinned items (lower = higher in the pinned list).
    var pinnedOrder: Int = 0
    var useCount: Int = 0
    @Attribute(.externalStorage) var imageData: Data?

    /// Typed accessor over the persisted raw string.
    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .plainText }
        set { contentTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        content: String,
        contentType: ContentType,
        timestamp: Date = .now,
        isPinned: Bool = false,
        pinnedOrder: Int = 0,
        useCount: Int = 0,
        imageData: Data? = nil
    ) {
        self.id = id
        self.content = content
        self.contentTypeRaw = contentType.rawValue
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.pinnedOrder = pinnedOrder
        self.useCount = useCount
        self.imageData = imageData
    }
}
```

Note: the old `struct` was `Equatable` by `id` and `Codable`. As a `@Model` class it is a reference type with stable identity; existing `item.id` comparisons in the panel still work. `@Model` is not `Codable` — migration uses `LegacyClipboardItem` (Task 4) instead.

- [ ] **Step 2: Build (expected to fail until store is ported)**

```bash
xcodegen generate && xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' build 2>&1 | tail -30
```
Expected: FAIL — `ClipboardStore.swift` and `ClipboardMonitor.swift` reference removed struct semantics (e.g. mutating `items` array, `Codable`). This is expected; Tasks 2-3 fix them. Do not commit yet.

---

## Task 2: Shared `ModelContainer` factory

**Files:**
- Create: `Hotstash/Clipboard/ModelContainer+Hotstash.swift`

- [ ] **Step 1: Create the container factory**

```swift
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
            return try ModelContainer(for: ClipboardItem.self, configurations: config)
        } catch {
            // A failed store is unrecoverable for a clipboard app; fall back to
            // a local-only store so the app still launches without sync.
            let local = ModelConfiguration("Hotstash", cloudKitDatabase: .none)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: ClipboardItem.self, configurations: local)
        }
    }()

    /// In-memory container for unit tests.
    static func hotstashInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipboardItem.self, configurations: config)
    }
}
```

- [ ] **Step 2: No build yet** — `ClipboardStore` (Task 3) consumes this. Proceed.

---

## Task 3: Reimplement `ClipboardStore` as a SwiftData facade

**Files:**
- Modify: `Hotstash/Clipboard/ClipboardStore.swift`

Preserve the public API used by call sites (`ClipboardPanelVC`, `MenuBarManager`, `MultiPastePanel`, `GeneralSettingsView`, `ClipboardMonitor`) while replacing internals. Replace the entire file contents.

- [ ] **Step 1: Replace the file**

```swift
import Foundation
import SwiftData

// MARK: - ClipboardStore

/// Clipboard history backed by SwiftData (and CloudKit via the shared container).
///
/// Text history is unbounded. Image bodies are capped by a rolling budget
/// (`maxImageCount` / `maxImageBytes`); the oldest non-pinned image items are
/// evicted first. Pinned items are never auto-evicted.
@MainActor
final class ClipboardStore {

    // MARK: Singleton / init

    static let shared = ClipboardStore()

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Production uses the shared CloudKit container; tests inject in-memory.
    init(container: ModelContainer = .hotstashShared) {
        self.container = container
    }

    // MARK: Image budget constants

    /// Keep at most this many image items.
    static let maxImageCount = 200
    /// Keep image bodies under this total byte budget (~50MB).
    static let maxImageBytes = 50 * 1024 * 1024

    // MARK: Reads

    /// All items, newest first. Use sparingly — prefer `recentItems(limit:offset:)`.
    var items: [ClipboardItem] {
        fetch(FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))
    }

    /// Pinned items, ordered by `pinnedOrder` then recency.
    var pinnedItems: [ClipboardItem] {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.pinnedOrder), SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = nil
        return fetch(descriptor)
    }

    /// A page of non-pinned items, newest first.
    func recentItems(limit: Int, offset: Int = 0) -> [ClipboardItem] {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return fetch(descriptor)
    }

    /// Count of non-pinned items.
    var recentCount: Int {
        (try? context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }
        ))) ?? 0
    }

    // MARK: Search

    /// Case-insensitive substring match across the full history (capped for UI).
    func search(query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.content.localizedStandardContains(trimmed) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return fetch(descriptor)
    }

    // MARK: Mutations

    func add(item: ClipboardItem) {
        context.insert(item)
        save()
        if item.imageData != nil { enforceImageBudget() }
    }

    func pin(id: UUID) {
        guard let item = item(id: id), !item.isPinned else { return }
        item.isPinned = true
        item.pinnedOrder = (pinnedItems.map(\.pinnedOrder).max() ?? -1) + 1
        save()
    }

    func unpin(id: UUID) {
        guard let item = item(id: id), item.isPinned else { return }
        item.isPinned = false
        save()
    }

    func remove(id: UUID) {
        guard let item = item(id: id) else { return }
        context.delete(item)
        save()
    }

    /// Deletes all non-pinned items.
    func clearAll() {
        try? context.delete(model: ClipboardItem.self, where: #Predicate { !$0.isPinned })
        save()
    }

    /// Reorders pinned items by reassigning `pinnedOrder`.
    func reorderPinned(from source: Int, to destination: Int) {
        var pinned = pinnedItems
        guard source >= 0, source < pinned.count,
              destination >= 0, destination <= pinned.count, source != destination
        else { return }
        let moved = pinned.remove(at: source)
        let insertAt = min(destination, pinned.count)
        pinned.insert(moved, at: insertAt)
        for (index, item) in pinned.enumerated() { item.pinnedOrder = index }
        save()
    }

    /// Bumps a non-pinned item to the top of the recent list (by recency).
    func moveToTop(id: UUID) {
        guard let item = item(id: id), !item.isPinned else { return }
        item.timestamp = .now
        save()
    }

    func recordUse(id: UUID) {
        guard let item = item(id: id) else { return }
        item.useCount += 1
        save()
    }

    // MARK: Image budget

    /// Evicts oldest non-pinned image items until both the count and byte
    /// budgets are satisfied. Pinned images are always retained.
    func enforceImageBudget() {
        var imageItems = fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.imageData != nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]  // newest first
        ))
        var totalBytes = imageItems.reduce(0) { $0 + ($1.imageData?.count ?? 0) }
        var changed = false
        // Evict from the oldest end while over budget.
        while (imageItems.count > Self.maxImageCount || totalBytes > Self.maxImageBytes),
              let oldest = imageItems.popLast() {
            totalBytes -= (oldest.imageData?.count ?? 0)
            context.delete(oldest)
            changed = true
        }
        if changed { save() }
    }

    // MARK: Private helpers

    private func item(id: UUID) -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func fetch(_ descriptor: FetchDescriptor<ClipboardItem>) -> [ClipboardItem] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        try? context.save()
    }
}
```

Note: the legacy `maxItems`/`recentItems` array property and `search` in-memory filter are gone. `recentItems` is now a function; `GeneralSettingsView` (Task 6) and `MultiPastePanel` (Task 9) are updated to match. `maxItems` removed entirely (text unlimited).

- [ ] **Step 2: No build yet** — call sites still reference old API; fixed in Tasks 5/6/9. Proceed; build runs in Task 5.

---

## Task 4: Legacy migration types + runner

**Files:**
- Create: `Hotstash/Clipboard/LegacyClipboardItem.swift`
- Create: `Hotstash/Clipboard/ClipboardMigration.swift`

- [ ] **Step 1: Create the legacy Codable mirror**

```swift
import Foundation

/// Codable mirror of the pre-SwiftData `ClipboardItem` struct, used only to
/// decode the legacy UserDefaults history during one-time migration.
struct LegacyClipboardItem: Codable {
    let id: UUID
    let content: String
    let contentType: ContentType
    let timestamp: Date
    let isPinned: Bool
    let useCount: Int
    let imageData: Data?
}
```

- [ ] **Step 2: Create the migration runner**

```swift
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
```

- [ ] **Step 3: No build yet** — wired in Task 5.

---

## Task 5: Port `ClipboardMonitor` (concealed filter + predicate de-dup), wire migration

**Files:**
- Modify: `Hotstash/Clipboard/ClipboardMonitor.swift`
- Modify: `Hotstash/App/AppDelegate.swift`

- [ ] **Step 1: Add concealed/transient filter and fix de-dup in `poll()`**

Replace the body of `poll()` (lines ~67-107) with:

```swift
    private func poll() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // If the app itself triggered this write, skip it.
        guard !isAppWriting else { return }

        // Never capture concealed/transient/auto-generated content
        // (passwords from password managers, one-time codes, etc.).
        if containsSensitiveType(pasteboard) { return }

        // Try image first.
        if let image = imageFromPasteboard(pasteboard) {
            let item = ClipboardItem(
                content: "[Image]",
                contentType: .image,
                imageData: thumbnailData(from: image)
            )
            ClipboardStore.shared.add(item: item)
            NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
            return
        }

        // Fall back to plain-string content.
        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty else { return }

        // De-dup: if identical non-pinned content already exists, bump it.
        let store = ClipboardStore.shared
        if let existing = store.recentItems(limit: 1).first, existing.content == content {
            // Already at top; nothing to do.
            return
        }
        if let dup = store.search(query: content).first(where: { !$0.isPinned && $0.content == content }) {
            store.moveToTop(id: dup.id)
            NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
            return
        }

        let type = ContentDetector.detect(content)
        let item = ClipboardItem(content: content, contentType: type)
        store.add(item: item)
        NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
    }

    /// Pasteboard marker types used by password managers and ephemeral copies.
    private func containsSensitiveType(_ pasteboard: NSPasteboard) -> Bool {
        let sensitive: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
        ]
        let present = (pasteboard.types ?? []).map(\.rawValue)
        return present.contains { sensitive.contains($0) }
    }
```

- [ ] **Step 2: Run migration before the monitor starts (`AppDelegate`)**

In `applicationDidFinishLaunching`, replace the `ClipboardMonitor.shared.start()` line (line 18) with:

```swift
        // Migrate legacy UserDefaults history into SwiftData, then boot the pipeline.
        ClipboardMigration.runIfNeeded(context: ClipboardStore.shared.modelContextForMigration)
        ClipboardMonitor.shared.start()
```

- [ ] **Step 3: Expose a migration context accessor on the store**

In `Hotstash/Clipboard/ClipboardStore.swift`, add inside the class (after `init`):

```swift
    /// Context used by one-time migration at launch.
    var modelContextForMigration: ModelContext { context }
```

- [ ] **Step 4: Build**

```bash
xcodegen generate && xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' build 2>&1 | tail -30
```
Expected: FAIL — `ClipboardPanelVC`, `GeneralSettingsView`, `MultiPastePanel` still use the removed `items`/`maxItems`/`recentItems`-as-property API. Fixed in Tasks 6 & 9. (If only those errors remain, proceed.)

---

## Task 6: Update `GeneralSettingsView` — remove text history-limit picker

**Files:**
- Modify: `Hotstash/UI/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Replace the History section's picker**

Replace the `Picker("History limit", ...) { ... }` block (lines ~70-81) with a static info row:

```swift
                LabeledContent("History") {
                    Text("Unlimited")
                        .foregroundStyle(.secondary)
                }
```

Leave the `Clear History` button and its confirmation dialog unchanged (still calls `ClipboardStore.shared.clearAll()`).

- [ ] **Step 2: Remove now-unused `historyLimit`/`historyLimits` state**

Delete the `@AppStorage`/`@State` for `historyLimit` and the `historyLimits` array near the top of the struct (search for `historyLimit`). Remove any `UserDefaults.standard.set(newValue, forKey: "historyLimit")` references.

- [ ] **Step 3: No build yet** — panel still broken; Task 9 follows. (Build at end of Task 9.)

---

## Task 7: Store unit tests (TDD — write, run red is moot since impl exists; verify green)

**Files:**
- Create: `HotstashTests/ClipboardStoreTests.swift`

> Note: implementation already exists (Task 3), so these tests verify behavior rather than drive it red-first. Each `@Test` uses a fresh in-memory store.

- [ ] **Step 1: Write the store tests**

```swift
import Testing
import SwiftData
@testable import Hotstash

@MainActor
struct ClipboardStoreTests {

    private func makeStore() throws -> ClipboardStore {
        let container = try ModelContainer.hotstashInMemory()
        return ClipboardStore(container: container)
    }

    @Test func addInsertsNewestFirst() throws {
        let store = try makeStore()
        store.add(item: ClipboardItem(content: "first", contentType: .plainText,
                                      timestamp: Date(timeIntervalSince1970: 1)))
        store.add(item: ClipboardItem(content: "second", contentType: .plainText,
                                      timestamp: Date(timeIntervalSince1970: 2)))
        let page = store.recentItems(limit: 10)
        #expect(page.map(\.content) == ["second", "first"])
    }

    @Test func pinAndUnpin() throws {
        let store = try makeStore()
        let item = ClipboardItem(content: "x", contentType: .plainText)
        store.add(item: item)
        store.pin(id: item.id)
        #expect(store.pinnedItems.map(\.id) == [item.id])
        #expect(store.recentItems(limit: 10).isEmpty)
        store.unpin(id: item.id)
        #expect(store.pinnedItems.isEmpty)
        #expect(store.recentItems(limit: 10).count == 1)
    }

    @Test func removeAndClearAllKeepsPinned() throws {
        let store = try makeStore()
        let a = ClipboardItem(content: "a", contentType: .plainText)
        let b = ClipboardItem(content: "b", contentType: .plainText)
        store.add(item: a); store.add(item: b)
        store.pin(id: a.id)
        store.clearAll()
        #expect(store.recentItems(limit: 10).isEmpty)
        #expect(store.pinnedItems.map(\.id) == [a.id])
        store.remove(id: a.id)
        #expect(store.pinnedItems.isEmpty)
    }

    @Test func searchMatchesCaseInsensitive() throws {
        let store = try makeStore()
        store.add(item: ClipboardItem(content: "Hello World", contentType: .plainText))
        store.add(item: ClipboardItem(content: "goodbye", contentType: .plainText))
        #expect(store.search(query: "hello").count == 1)
        #expect(store.search(query: "O").count == 2)
    }

    @Test func reorderPinnedByOrder() throws {
        let store = try makeStore()
        let a = ClipboardItem(content: "a", contentType: .plainText)
        let b = ClipboardItem(content: "b", contentType: .plainText)
        let c = ClipboardItem(content: "c", contentType: .plainText)
        for i in [a, b, c] { store.add(item: i); store.pin(id: i.id) }
        // pinned order is a, b, c. Move index 0 -> 2.
        store.reorderPinned(from: 0, to: 2)
        #expect(store.pinnedItems.map(\.content) == ["b", "c", "a"])
    }

    @Test func recordUseIncrements() throws {
        let store = try makeStore()
        let item = ClipboardItem(content: "x", contentType: .plainText)
        store.add(item: item)
        store.recordUse(id: item.id)
        store.recordUse(id: item.id)
        #expect(store.recentItems(limit: 1).first?.useCount == 2)
    }

    @Test func imageBudgetEvictsOldestNonPinned() throws {
        let store = try makeStore()
        // Force a tiny budget by adding > maxImageCount is impractical here;
        // instead verify byte-budget eviction with a few large blobs by
        // exceeding the count via many small images.
        // Add maxImageCount + 5 image items; oldest 5 evicted.
        let total = ClipboardStore.maxImageCount + 5
        for i in 0..<total {
            store.add(item: ClipboardItem(
                content: "[Image]", contentType: .image,
                timestamp: Date(timeIntervalSince1970: TimeInterval(i)),
                imageData: Data([UInt8(i % 255)])
            ))
        }
        let imageCount = store.recentItems(limit: total).filter { $0.contentType == .image }.count
        #expect(imageCount == ClipboardStore.maxImageCount)
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
xcodegen generate && xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' test -only-testing:HotstashTests/ClipboardStoreTests 2>&1 | tail -30
```
Expected: all pass. (If the project doesn't yet build because the panel is unported, temporarily this test target still compiles against `Hotstash`; if blocked, do Task 9 first then return. The two are independent of each other's logic.)

> **Ordering note:** Task 9 (panel) must build before `test` can run, because the test target links the app. If you hit app-build errors here, complete Task 9, then run this step.

- [ ] **Step 3: Commit**

```bash
git add HotstashTests/ClipboardStoreTests.swift
git commit -m "test: ClipboardStore SwiftData facade unit tests"
```

---

## Task 8: Migration unit tests

**Files:**
- Create: `HotstashTests/ClipboardMigrationTests.swift`

- [ ] **Step 1: Write the migration tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import Hotstash

@MainActor
struct ClipboardMigrationTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer.hotstashInMemory()
        return container.mainContext
    }

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "migration-test-\(UUID().uuidString)")!
        return suite
    }

    @Test func migratesLegacyItemsAndClearsKeys() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let legacy = [
            LegacyClipboardItem(id: UUID(), content: "one", contentType: .plainText,
                                timestamp: .now, isPinned: true, useCount: 3, imageData: nil),
            LegacyClipboardItem(id: UUID(), content: "two", contentType: .url,
                                timestamp: .now, isPinned: false, useCount: 0, imageData: nil),
        ]
        let data = try JSONEncoder().encode(legacy)
        defaults.set(data, forKey: "com.zeyadamer.hotstash.clipboardItems")

        let count = ClipboardMigration.runIfNeeded(context: context, defaults: defaults)
        #expect(count == 2)

        let stored = try context.fetch(FetchDescriptor<ClipboardItem>())
        #expect(stored.count == 2)
        #expect(stored.contains { $0.content == "one" && $0.isPinned && $0.useCount == 3 })
        #expect(defaults.bool(forKey: "com.zeyadamer.hotstash.didMigrateToSwiftData"))
        #expect(defaults.data(forKey: "com.zeyadamer.hotstash.clipboardItems") == nil)
    }

    @Test func isIdempotent() throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        defaults.set(true, forKey: "com.zeyadamer.hotstash.didMigrateToSwiftData")
        let count = ClipboardMigration.runIfNeeded(context: context, defaults: defaults)
        #expect(count == 0)
        #expect(try context.fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' test -only-testing:HotstashTests/ClipboardMigrationTests 2>&1 | tail -30
```
Expected: both pass (after Task 9 makes the app build).

- [ ] **Step 3: Commit**

```bash
git add HotstashTests/ClipboardMigrationTests.swift
git commit -m "test: clipboard migration unit tests"
```

---

## Task 9: Port `ClipboardPanelVC` paging + `MultiPastePanel`

**Files:**
- Modify: `Hotstash/UI/Panel/ClipboardPanelVC.swift`
- Modify: `Hotstash/UI/MultiPaste/MultiPastePanel.swift`

- [ ] **Step 1: Add paging state to `ClipboardPanelVC`**

Near the other stored properties (top of the class), add:

```swift
    /// Number of recent items fetched per page.
    private let pageSize = 100
    /// How many recent pages are currently loaded.
    private var loadedRecentCount = 0
```

- [ ] **Step 2: Rewrite `applySearch` to be tab-aware and paged**

Replace `applySearch(query:)` (lines ~488-505) with:

```swift
    private func applySearch(query: String) {
        let store = ClipboardStore.shared
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if !trimmed.isEmpty {
            // Search spans full history; split by current tab below.
            let results = store.search(query: trimmed)
            filteredItems = currentTab == 0
                ? results.filter { !$0.isPinned }
                : results.filter {  $0.isPinned }
        } else if currentTab == 1 {
            filteredItems = store.pinnedItems
        } else {
            loadedRecentCount = pageSize
            filteredItems = store.recentItems(limit: loadedRecentCount)
        }

        if TrialManager.shared.isRestricted {
            filteredItems = Array(filteredItems.prefix(TrialManager.freeHistoryLimit))
        }

        rebuildRows()
        tableView.reloadData()
        updateToolbarState()
    }

    /// Appends the next page of recent items (recent tab, no active search).
    private func loadMoreIfNeeded(currentRow: Int) {
        guard currentTab == 0,
              searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty,
              !TrialManager.shared.isRestricted,
              currentRow >= rows.count - 10,
              filteredItems.count >= loadedRecentCount  // a full page was returned
        else { return }
        loadedRecentCount += pageSize
        filteredItems = ClipboardStore.shared.recentItems(limit: loadedRecentCount)
        rebuildRows()
        tableView.reloadData()
    }
```

- [ ] **Step 3: Simplify `rebuildRows` (filteredItems is already tab-scoped)**

Replace `rebuildRows()` (lines ~507-513) with:

```swift
    private func rebuildRows() {
        rows = filteredItems.map { .item($0) }
    }
```

- [ ] **Step 4: Trigger load-more from the table data source**

In the `NSTableViewDelegate`/`DataSource` `tableView(_:viewFor:row:)` method (search for `viewFor tableColumn`), add at the top of the method body:

```swift
        loadMoreIfNeeded(currentRow: row)
```

- [ ] **Step 5: Fix `updateToolbarState` clear-all check**

Replace the `clearAllButton.isEnabled` line (line ~541):

```swift
        clearAllButton.isEnabled  = currentTab == 0 && ClipboardStore.shared.recentCount > 0
```

- [ ] **Step 6: Fix `MultiPastePanel` recent-items access**

In `Hotstash/UI/MultiPaste/MultiPastePanel.swift` line ~167, replace:

```swift
            let items = ClipboardStore.shared.recentItems
```
with:
```swift
            let items = ClipboardStore.shared.recentItems(limit: 200)
```

- [ ] **Step 7: Build**

```bash
xcodegen generate && xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' build 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Run the full test suite**

```bash
xcodebuild -project Hotstash.xcodeproj -scheme Hotstash -destination 'platform=macOS' test 2>&1 | tail -30
```
Expected: all `ClipboardStoreTests` + `ClipboardMigrationTests` pass.

- [ ] **Step 9: Commit**

```bash
git add Hotstash/Clipboard Hotstash/App/AppDelegate.swift Hotstash/UI project.yml
git commit -m "feat: SwiftData store, unlimited history, paging, concealed-copy filter, migration"
```

---

## Task 10: Manual verification (no automated coverage)

Not unit-testable. Perform manually; record results.

- [ ] **Step 1: Migration smoke** — install over a build that has existing UserDefaults history; launch; confirm prior items appear and `didMigrateToSwiftData` is set (legacy keys gone).
- [ ] **Step 2: Concealed filter** — copy a password from a password manager (1Password/Keychain); confirm it does NOT appear in history. Copy normal text; confirm it does.
- [ ] **Step 3: Unlimited + paging** — copy > 150 distinct text items; scroll the panel; confirm older items load and search finds an item beyond the first page.
- [ ] **Step 4: Image cap** — copy many images; confirm count stays at/below 200 and oldest images drop; pinned image survives.
- [ ] **Step 5: CloudKit (two Macs, same Apple ID)** — copy on Mac A → appears on Mac B within seconds; delete on B → removed on A; pin syncs.

- [ ] **Step 6: CloudKit production schema (release gate)** — in CloudKit Dashboard, deploy the auto-created `ClipboardItem` record type from Development to Production before App Store submission. (External step; cannot be automated here.)

---

## Release Checklist (carried from spec)

- [ ] CloudKit container `iCloud.com.zeyadamer.hotstash` exists in the Apple Developer account.
- [ ] CloudKit schema deployed to Production.
- [ ] App version/build bumped in `Info.plist`.
- [ ] What's New copy mentions iCloud sync + unlimited history.
