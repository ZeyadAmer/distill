import Testing
@testable import Hotstash

/// A minimal stub transform for merge tests (no engine needed).
private struct StubTransform: Transform {
    let id: String
    var name: String { id }
    var icon: String { "circle" }
    var category: TransformCategory { .cleanup }
    var applicableTo: [ContentType] { [] }
    func apply(to input: String) -> String { input }
}

struct TransformRegistryMergeTests {

    @Test func mergeAppendsCustom() {
        let merged = TransformRegistry.merge(
            builtIn: [StubTransform(id: "a"), StubTransform(id: "b")],
            custom: [StubTransform(id: "c")]
        )
        #expect(merged.map { $0.id } == ["a", "b", "c"])
    }

    @Test func mergeDropsCollidingCustom() {
        let merged = TransformRegistry.merge(
            builtIn: [StubTransform(id: "a"), StubTransform(id: "b")],
            custom: [StubTransform(id: "a"), StubTransform(id: "c")]
        )
        // Colliding custom "a" dropped; built-in retained; "c" appended.
        #expect(merged.map { $0.id } == ["a", "b", "c"])
    }

    @Test func mergeEmptyCustom() {
        let builtIn: [any Transform] = [StubTransform(id: "a"), StubTransform(id: "b")]
        let merged = TransformRegistry.merge(builtIn: builtIn, custom: [])
        #expect(merged.map { $0.id } == ["a", "b"])
    }

    @Test func registryIncludesCustomViaProvider() {
        // Inject a custom provider via the test-only initializer (does not touch the singleton).
        let registry = TransformRegistry(customProvider: { [StubTransform(id: "my.custom.slug")] })
        #expect(registry.orderedAll.contains { $0.id == "my.custom.slug" })
        #expect(registry.enabled.contains { $0.id == "my.custom.slug" })
    }
}
