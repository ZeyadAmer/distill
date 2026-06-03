import Foundation
import SwiftData
import Testing
@testable import Hotstash

@MainActor
struct MarketplaceLibraryTests {

    // MARK: - Helpers

    /// Builds a library backed by a fresh in-memory container.
    /// The container is returned so the caller can hold it for the test's
    /// lifetime — ModelContext does not retain its container.
    private func makeLibrary() throws -> (MarketplaceLibrary, ModelContainer) {
        let container = try ModelContainer.hotstashInMemory()
        return (MarketplaceLibrary(container: container), container)
    }

    private func textManifest(
        slug: String,
        name: String,
        js: String = "function transform(i){return i}"
    ) -> TransformManifest {
        TransformManifest(
            slug: slug,
            kind: .text,
            name: name,
            description: "desc",
            icon: "textformat",
            category: "Case",
            body: .text(js: js)
        )
    }

    // MARK: - CRUD

    @Test func upsertInsertsThenUpdates() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        lib.upsert(manifest: textManifest(slug: "x", name: "A"), origin: "local")
        #expect(lib.all().count == 1)

        lib.upsert(manifest: textManifest(slug: "x", name: "B"), origin: "local")
        #expect(lib.all().count == 1)
        #expect(lib.stored(slug: "x")?.manifest?.name == "B")
    }

    @Test func installedVsLocalFilter() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        lib.upsert(manifest: textManifest(slug: "draft", name: "Draft"), origin: "local")
        lib.upsert(manifest: textManifest(slug: "inst", name: "Installed"), origin: "installed")

        #expect(lib.localDrafts().count == 1)
        #expect(lib.installed().count == 1)
        #expect(lib.localDrafts().first?.slug == "draft")
        #expect(lib.installed().first?.slug == "inst")
    }

    @Test func deleteRemoves() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        lib.upsert(manifest: textManifest(slug: "x", name: "A"), origin: "local")
        lib.delete(slug: "x")
        #expect(lib.all().isEmpty)
    }

    @Test func customTransformsMapping() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        let manifest = textManifest(
            slug: "upper",
            name: "Upper",
            js: "function transform(i){return i.toUpperCase()}"
        )
        lib.upsert(manifest: manifest, origin: "local")

        let transforms = lib.customTransforms()
        let match = try #require(transforms.first { $0.id == "upper" })
        #expect(match.apply(to: "hi") == "HI")
    }

    @Test func corruptRowSkipped() throws {
        let (lib, container) = try makeLibrary()
        let context = container.mainContext

        // A valid row plus a directly-inserted corrupt row.
        lib.upsert(manifest: textManifest(slug: "good", name: "Good"), origin: "local")
        context.insert(StoredTransform(slug: "bad", manifestJSON: Data([0x00])))
        try context.save()

        // Two rows persist, but only the decodable one maps to a transform.
        #expect(lib.all().count == 2)
        let transforms = lib.customTransforms()
        #expect(transforms.count == 1)
        #expect(transforms.first?.id == "good")
    }

    // MARK: - Import / Export

    @Test func exportImportRoundTrip() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        let manifest = textManifest(slug: "round", name: "Round Trip")
        let data = try lib.exportData(manifest)
        let decoded = try lib.importManifest(from: data)

        #expect(decoded.slug == manifest.slug)
        #expect(decoded.name == manifest.name)
        #expect(decoded.kind == manifest.kind)
    }

    @Test func importInvalidThrows() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        let data = Data("{}".utf8)
        #expect(throws: MarketplaceLibraryError.self) {
            try lib.importManifest(from: data)
        }
    }

    @Test func setPublishedFlag() throws {
        let (lib, container) = try makeLibrary()
        _ = container

        lib.upsert(manifest: textManifest(slug: "x", name: "A"), origin: "local")
        lib.setPublished(slug: "x", true)
        #expect(lib.stored(slug: "x")?.isPublished == true)
    }
}
