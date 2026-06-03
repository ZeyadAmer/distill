import Foundation
import OSLog
import SwiftData

// MARK: - MarketplaceLibrary

/// Local library of marketplace transforms backed by SwiftData.
///
/// Owns the `StoredTransform` table: CRUD over locally-authored drafts and
/// installed transforms, plus file import/export of manifests. The registry
/// consumes ``customTransforms()`` to surface custom rows alongside built-ins.
///
/// Mirrors `ClipboardStore`'s structure: a `@MainActor` facade over the shared
/// container's `mainContext`, with an injectable container for tests.
@MainActor
final class MarketplaceLibrary {

    // MARK: Singleton / init

    static let shared = MarketplaceLibrary()

    /// File extension for exported/imported single-transform manifests.
    static let fileExtension = "hotstashtransform"

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "MarketplaceLibrary")

    /// Production uses the shared CloudKit container; tests inject in-memory.
    init(container: ModelContainer = .hotstashShared) {
        self.container = container
    }

    // MARK: Reads

    /// All stored transforms, most recently updated first.
    func all() -> [StoredTransform] {
        fetch(FetchDescriptor<StoredTransform>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    /// Installed transforms (origin == "installed"), most recently updated first.
    func installed() -> [StoredTransform] {
        fetch(FetchDescriptor<StoredTransform>(
            predicate: #Predicate { $0.origin == "installed" },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    /// Locally-authored drafts (origin == "local"), most recently updated first.
    func localDrafts() -> [StoredTransform] {
        fetch(FetchDescriptor<StoredTransform>(
            predicate: #Predicate { $0.origin == "local" },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    /// The stored row for `slug`, if any.
    func stored(slug: String) -> StoredTransform? {
        var descriptor = FetchDescriptor<StoredTransform>(
            predicate: #Predicate { $0.slug == slug }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// Every stored manifest adapted to the app's `Transform` protocol.
    ///
    /// Rows whose persisted JSON fails to decode are skipped — a corrupt row
    /// never crashes or omits the rest of the library.
    func customTransforms() -> [any Transform] {
        all().compactMap { stored -> (any Transform)? in
            guard let manifest = stored.manifest else { return nil }
            return MarketplaceTransform(manifest: manifest)
        }
    }

    // MARK: Mutations

    /// Inserts a new row for `manifest.slug`, or updates the existing one in place.
    /// Re-encodes the manifest and bumps `updatedAt`. Returns the persisted row.
    @discardableResult
    func upsert(
        manifest: TransformManifest,
        origin: String,
        installedVersion: Int = 0,
        isPublished: Bool = false
    ) -> StoredTransform {
        let json = (try? TransformManifestCodec.encode(manifest)) ?? Data()
        let now = Date.now

        if let existing = stored(slug: manifest.slug) {
            existing.manifestJSON = json
            existing.origin = origin
            existing.installedVersion = installedVersion
            existing.isPublished = isPublished
            existing.updatedAt = now
            save()
            return existing
        }

        let row = StoredTransform(
            slug: manifest.slug,
            manifestJSON: json,
            origin: origin,
            installedVersion: installedVersion,
            isPublished: isPublished,
            updatedAt: now
        )
        context.insert(row)
        save()
        return row
    }

    /// Deletes the stored row for `slug`, if present.
    func delete(slug: String) {
        guard let row = stored(slug: slug) else { return }
        context.delete(row)
        save()
    }

    /// Sets the published flag on the stored row for `slug`, if present.
    func setPublished(slug: String, _ value: Bool) {
        guard let row = stored(slug: slug) else { return }
        row.isPublished = value
        row.updatedAt = .now
        save()
    }

    // MARK: Import / Export

    /// Encodes `manifest` to the canonical JSON used for `.hotstashtransform` files.
    func exportData(_ manifest: TransformManifest) throws -> Data {
        try TransformManifestCodec.encode(manifest)
    }

    /// Decodes and validates a manifest from file `data`.
    ///
    /// Does not persist — the caller decides whether to ``upsert(manifest:origin:installedVersion:isPublished:)``.
    /// Throws ``MarketplaceLibraryError/invalidManifest(_:)`` on malformed JSON or
    /// when required fields (slug, name) are empty.
    func importManifest(from data: Data) throws -> TransformManifest {
        let manifest: TransformManifest
        do {
            manifest = try TransformManifestCodec.decode(data)
        } catch {
            throw MarketplaceLibraryError.invalidManifest("Could not decode manifest: \(error.localizedDescription)")
        }

        let slug = manifest.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            throw MarketplaceLibraryError.invalidManifest("Manifest is missing a slug")
        }
        guard !name.isEmpty else {
            throw MarketplaceLibraryError.invalidManifest("Manifest is missing a name")
        }
        return manifest
    }

    // MARK: Private helpers

    private func fetch(_ descriptor: FetchDescriptor<StoredTransform>) -> [StoredTransform] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("SwiftData save failed: \(error, privacy: .public)")
        }
    }
}

// MARK: - MarketplaceLibraryError

/// Errors surfaced by ``MarketplaceLibrary`` import/validation.
enum MarketplaceLibraryError: Error {
    /// The manifest could not be decoded or failed basic validation.
    case invalidManifest(String)
}
