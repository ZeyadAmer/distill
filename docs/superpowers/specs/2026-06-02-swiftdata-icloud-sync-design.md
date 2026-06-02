# Design: SwiftData Storage Rewrite + Unlimited History + iCloud Sync

**Date:** 2026-06-02
**Status:** Approved (pending spec review)
**Scope:** macOS app only. Marketplace for transforms is a separate, later spec cycle.

## Summary

Replace Hotstash's UserDefaults-backed clipboard history with a SwiftData store,
remove the hard item cap (text history becomes unlimited), and mirror history to
the user's private iCloud database via CloudKit so it syncs across their Macs and
survives reinstall.

This is the first of two planned spec cycles. The transforms **marketplace**
(user-uploaded transforms + backend) is explicitly out of scope here and will be
designed separately — it requires a declarative/sandboxed transform format and
server infrastructure that do not exist today.

## Decisions (locked during brainstorming)

| Decision | Choice |
| --- | --- |
| Persistence framework | **SwiftData + CloudKit** |
| Minimum OS | macOS **13 → 14** |
| Platforms | **macOS only** — iOS app/extensions shelved |
| iCloud model | Full Mac↔Mac sync + backup/restore (private DB) |
| Sensitive content | **Never captured** (concealed/transient pasteboard types skipped) |
| Text history | **Unlimited** |
| Image history | **Rolling cap: ~200 images / 50MB byte budget**, oldest evicted first |
| iOS targets | **Shelved** — source kept on disk, removed from `project.yml`/build |

## Non-Goals

- Transforms marketplace (separate spec).
- iOS app, Share extension, Controls extension (shelved, not deleted).
- Cross-Apple-ID / shared-with-others sync (private DB only).
- Backwards compatibility with macOS 13.

---

## 1. Target & Build Cleanup

- Bump macOS deployment target `13.0 → 14.0` in `project.yml` (`options.deploymentTarget.macOS`,
  `settings.base.MACOSX_DEPLOYMENT_TARGET`, and the `Hotstash` target overrides).
- Remove iOS targets and their schemes from `project.yml`: `HotstashIOS`, `HotstashShare`,
  `HotstashControls`, schemes `HotstashIOS` and `HotstashControls-History`.
  **Leave the source folders on disk** (`HotstashIOS/`, `HotstashShare/`, `HotstashControls/`)
  so future marketplace/mobile work can resume.
- Add iCloud capability to the macOS app:
  - Entitlements (`Hotstash/Resources/Hotstash.entitlements`):
    - `com.apple.developer.icloud-container-identifiers` → `[iCloud.com.zeyadamer.hotstash]`
    - `com.apple.developer.icloud-services` → `["CloudKit"]`
    - `com.apple.security.network.client` → `true` (sandbox: CloudKit needs network)
  - Keep existing `app-sandbox` and `automation.apple-events`.
- Regenerate project with `xcodegen`.

## 2. Data Model

`ClipboardItem` moves from an immutable `struct` to a SwiftData `@Model final class`.
CloudKit mirroring imposes constraints, all of which this model respects:

- Every stored property has a default value (CloudKit requirement).
- No `@Attribute(.unique)` (CloudKit forbids unique constraints) — uniqueness by
  `id` is enforced in store code.
- Large binary uses `@Attribute(.externalStorage)` → stored as a file locally and
  uploaded as a `CKAsset` when synced.

```swift
@Model
final class ClipboardItem {
    var id: UUID = UUID()
    var content: String = ""
    var contentTypeRaw: String = ContentType.plainText.rawValue
    var timestamp: Date = Date.now
    var isPinned: Bool = false
    var pinnedOrder: Int = 0      // stable sort order among pinned items
    var useCount: Int = 0
    @Attribute(.externalStorage) var imageData: Data?

    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .plainText }
        set { contentTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), content: String, contentType: ContentType,
         timestamp: Date = .now, isPinned: Bool = false, pinnedOrder: Int = 0,
         useCount: Int = 0, imageData: Data? = nil) {
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

`ContentType` stays an enum in `ContentDetector.swift`; its `String` raw value is
persisted via `contentTypeRaw`. The existing `ClipboardItem` UI extensions
(`displayName`, `badgeColor` on `ContentType`) are unaffected.

## 3. Store Layer — `ClipboardStore` as a Facade

**Approach:** keep the existing `ClipboardStore.shared` public API and reimplement
its internals on top of a SwiftData `ModelContext`, rather than spreading `@Query`
through the views.

Rationale: the UI is AppKit (`NSPanel`, `NSViewController`, `NSCollectionView`-style
cells), where SwiftUI's `@Query` does not apply. Keeping the facade preserves every
call site (`ClipboardPanelVC`, `MenuBarManager`, `ClipboardMonitor`, `MultiPastePanel`)
and confines the rewrite to one file.

```swift
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    // Public API preserved:
    func add(item: ClipboardItem)
    func pin(id: UUID); func unpin(id: UUID)
    func remove(id: UUID); func clearAll()
    func reorderPinned(from: Int, to: Int)
    func moveToTop(id: UUID); func recordUse(id: UUID)
    func search(query: String) -> [ClipboardItem]

    // New paging API for the panel:
    func page(offset: Int, limit: Int) -> [ClipboardItem]
    var pinnedItems: [ClipboardItem] { get }   // fetched via predicate isPinned == true
}
```

Internals:
- Mutations insert/delete `@Model` objects and call `context.save()`.
- Reads use `FetchDescriptor<ClipboardItem>` with `#Predicate`, `SortDescriptor`
  (`timestamp` desc), and `fetchLimit`/`fetchOffset` for paging.
- `reorderPinned` uses the `pinnedOrder` property (§2) to sort pinned items, since
  array-index reordering no longer applies to a DB.

## 4. Unlimited History, Paging, Image Cap

- **Text: unlimited.** The `maxItems`/`enforceLimit()` text eviction is removed.
- **Paging:** `ClipboardPanelVC` fetches the newest ~100 items via `page(offset:limit:)`
  and loads further pages as the user scrolls. Avoids materializing unbounded history.
- **Search:** runs as a `#Predicate` (`content.localizedStandardContains(query)`) against
  the DB so it covers the full unlimited history, not just a loaded page. Replaces the
  current in-memory `.filter`.
- **Image rolling cap:** after each image insert (and once after each CloudKit merge),
  run `enforceImageBudget()`:
  - Keep newest images until **both** count ≤ 200 **and** total `imageData` bytes ≤ 50MB.
  - Evict oldest **non-pinned** image items first. Pinned images always retained.
  - Eviction deletes the whole item (image items have no useful text body — content is `"[Image]"`).
  - Budget constants live in one place; a Settings control to tune them is a later, optional addition.

## 5. CloudKit Sync

- Configure SwiftData with the private CloudKit database:

```swift
let config = ModelConfiguration(
    "Hotstash",
    cloudKitDatabase: .private("iCloud.com.zeyadamer.hotstash")
)
let container = try ModelContainer(for: ClipboardItem.self, configurations: config)
```

- Sync is automatic once the entitlement + container exist; SwiftData mirrors the
  store to the user's **private** CloudKit DB. No custom sync code.
- **Conflict handling:** SwiftData merge is last-writer-wins per record. Twin entries
  from two Macs copying identical text are prevented by `id`/content de-dup in `add()`
  (see §6) — but cross-device near-simultaneous copies of *different* text simply
  both appear, which is correct.
- **Image cap is device-local**, applied after merge, so one Mac with many images does
  not force eviction policy onto another (each device keeps its own newest-200/50MB view;
  the underlying records still exist in CloudKit until evicted everywhere). *Note: local
  eviction deletes the record, which propagates the delete. Acceptable: oldest images age
  out globally, newest always retained. Documented as intended behavior.*
- **First-run CloudKit schema:** development schema is auto-created from the model on
  first sync in debug; must be **deployed to production** in CloudKit Dashboard before
  App Store release. Captured in the implementation plan as a release checklist item.

## 6. Capture Changes — `ClipboardMonitor`

- **Concealed/transient filter (new):** in `poll()`, before capturing, inspect
  `pasteboard.types` and skip if any of these are present:
  - `org.nspasteboard.ConcealedType` (password managers)
  - `org.nspasteboard.TransientType`
  - `org.nspasteboard.AutoGeneratedType`

  Implemented as a guard returning early — concealed/transient content never enters
  history (local or cloud).
- Existing de-dup (`moveToTop` when identical non-pinned content exists) is preserved,
  reimplemented against the store's predicate-based lookup.
- Image thumbnailing (400px max, JPEG 0.7) unchanged.

## 7. Migration (One-Time)

On first launch after the update:

1. Guard on `UserDefaults` flag `com.zeyadamer.hotstash.didMigrateToSwiftData`.
2. Read legacy history blob (`com.zeyadamer.hotstash.clipboardItems`), decode
   `[LegacyClipboardItem]` (a `Codable` mirror of the old struct).
3. Insert each as a SwiftData `ClipboardItem`, preserving `id`, `content`,
   `contentType`, `timestamp`, `isPinned`, `useCount`, `imageData`.
4. `context.save()`, set the flag, remove the legacy `UserDefaults` keys
   (`clipboardItems`, `maxItems`).
5. Run `enforceImageBudget()` once post-migration.

Migration runs synchronously on the main actor at launch before the monitor starts,
so there is no window where new captures race the migration.

## 8. Testing

Framework: **Swift Testing** (`import Testing`), in-memory container per test.

```swift
let config = ModelConfiguration(isStoredInMemoryOnly: true)
let container = try ModelContainer(for: ClipboardItem.self, configurations: config)
```

Unit tests:
- `add` inserts; newest-first ordering via `page`.
- `pin`/`unpin`/`reorderPinned` with `pinnedOrder`.
- `remove`/`clearAll` (clearAll keeps pinned).
- `search` predicate: matches case-insensitively across full history.
- `moveToTop` de-dup: identical content does not create a twin.
- `enforceImageBudget`: evicts oldest non-pinned images past count/byte budget; keeps pinned.
- `recordUse` increments.
- Migration: seed legacy UserDefaults blob → migrate → assert SwiftData contents + flag set + legacy keys removed.

Not unit-tested (manual test plan in implementation plan):
- Concealed-type filtering (requires real pasteboard with marker types — covered by a
  small integration check + manual verification with a password manager).
- CloudKit sync (requires two Macs + iCloud account) — manual two-device test:
  copy on Mac A → appears on Mac B; delete on B → removed on A; image cap holds per device.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| SwiftData+CloudKit rough edges with large datasets | Paging + image budget keep working set small; text rows are tiny. |
| CloudKit schema not deployed to prod → release sync breaks | Release checklist item to deploy schema in CloudKit Dashboard. |
| Migration data loss | Migration is additive; legacy keys removed only after successful `save()`. Covered by test. |
| Sandbox blocks CloudKit | Add `network.client` entitlement; verify in QA. |
| Local image eviction propagates deletes across devices | Documented as intended (oldest images age out globally, newest retained). |

## Open Items for Implementation Plan

- Exact paging size and scroll-trigger threshold in `ClipboardPanelVC`.
- Whether `MultiPastePanel` needs paging or operates on the loaded page only.
- Settings UI for image budget (deferred / optional).
