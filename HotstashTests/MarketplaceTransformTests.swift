import Foundation
import SwiftData
import Testing
@testable import Hotstash

struct MarketplaceTransformTests {
    // MARK: - Helpers

    private func textManifest(
        js: String,
        slug: String = "uppercase",
        name: String = "Uppercase",
        category: String = "Case"
    ) -> TransformManifest {
        TransformManifest(
            slug: slug,
            kind: .text,
            name: name,
            description: "desc",
            icon: "textformat",
            category: category,
            body: .text(js: js)
        )
    }

    private func imageManifest() -> TransformManifest {
        TransformManifest(
            slug: "grayscale",
            kind: .image,
            name: "Grayscale",
            description: "desc",
            icon: "photo",
            category: "Image",
            body: .image(steps: [ImageStep(type: "grayscale")])
        )
    }

    // MARK: - Text adapter

    @Test("Text adapter applies the manifest JS")
    func textAdapterApplies() {
        let transform = MarketplaceTransform(
            manifest: textManifest(js: "function transform(i){return i.toUpperCase()}")
        )
        #expect(transform.apply(to: "hi") == "HI")
    }

    @Test("Text adapter returns input unchanged when the JS errors")
    func textAdapterErrorReturnsInput() {
        let transform = MarketplaceTransform(
            manifest: textManifest(js: "this is not valid javascript ((")
        )
        #expect(transform.apply(to: "hi") == "hi")
    }

    @Test("Image adapter returns nil for a text manifest")
    func imageAdapterNilForText() {
        let transform = MarketplaceTransform(
            manifest: textManifest(js: "function transform(i){return i}")
        )
        // Text manifests short-circuit to nil regardless of the data passed in.
        #expect(transform.applyToImageData(Data()) == nil)
    }

    // MARK: - Metadata mapping

    @Test("Category string maps to TransformCategory with cleanup fallback")
    func categoryMapping() {
        let json = MarketplaceTransform(manifest: textManifest(js: "", category: "JSON"))
        #expect(json.category == .json)

        let bogus = MarketplaceTransform(manifest: textManifest(js: "", category: "bogus"))
        #expect(bogus.category == .cleanup)
    }

    @Test("applicableTo reflects the manifest kind")
    func applicableTo() {
        let text = MarketplaceTransform(manifest: textManifest(js: ""))
        #expect(text.applicableTo == [])

        let image = MarketplaceTransform(manifest: imageManifest())
        #expect(image.applicableTo == [.image])
    }

    // MARK: - Persistence

    @Test("Manifest round-trips through StoredTransform")
    func storedRoundTrip() throws {
        let manifest = textManifest(js: "function transform(i){return i}")
        let data = try TransformManifestCodec.encode(manifest)

        let stored = StoredTransform(slug: manifest.slug, manifestJSON: data)
        let decoded = try #require(stored.manifest)

        #expect(decoded.slug == manifest.slug)
        #expect(decoded.name == manifest.name)
        #expect(decoded.kind == manifest.kind)
    }

    @Test("In-memory container persists and re-fetches a StoredTransform")
    @MainActor
    func containerPersistsStored() throws {
        // Hold the container for the test's lifetime — ModelContext does not retain it.
        let container = try ModelContainer.hotstashInMemory()
        let context = container.mainContext

        let manifest = textManifest(js: "function transform(i){return i}")
        let data = try TransformManifestCodec.encode(manifest)
        context.insert(StoredTransform(slug: manifest.slug, manifestJSON: data))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StoredTransform>())
        #expect(fetched.count == 1)

        let stored = try #require(fetched.first)
        let decoded = try #require(stored.manifest)
        #expect(decoded.slug == manifest.slug)
    }
}
