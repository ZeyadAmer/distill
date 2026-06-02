import Foundation
import Testing
@testable import Hotstash

struct TransformManifestTests {
    // MARK: - Round-trip: text manifest

    @Test("Text manifest round-trips through the codec unchanged")
    func textManifestRoundTrips() throws {
        let original = TransformManifest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            slug: "uppercase",
            version: 3,
            kind: .text,
            name: "Uppercase",
            description: "Uppercases the text",
            icon: "textformat",
            category: "Case",
            authorId: "author-1",
            authorName: "Ada",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            body: .text(js: "return input.toUpperCase();")
        )

        let data = try TransformManifestCodec.encode(original)
        let decoded = try TransformManifestCodec.decode(data)

        #expect(decoded == original)
    }

    // MARK: - Round-trip: image manifest

    @Test("Image manifest with mixed param types round-trips unchanged")
    func imageManifestRoundTrips() throws {
        let steps: [ImageStep] = [
            ImageStep(type: "resize", params: [
                "scale": .double(0.5),
                "preserveAspect": .bool(true),
                "format": .string("png")
            ]),
            ImageStep(type: "rotate", params: [
                "degrees": .int(90)
            ])
        ]

        let original = TransformManifest(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            slug: "resize-rotate",
            version: 1,
            kind: .image,
            name: "Resize & Rotate",
            description: "Scales and rotates the image",
            icon: "photo",
            category: "Image",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: .image(steps: steps)
        )

        let data = try TransformManifestCodec.encode(original)
        let decoded = try TransformManifestCodec.decode(data)

        #expect(decoded == original)
        if case let .image(decodedSteps) = decoded.body {
            #expect(decodedSteps.count == 2)
            #expect(decodedSteps[0].params["scale"]?.doubleValue == 0.5)
            #expect(decodedSteps[0].params["preserveAspect"]?.boolValue == true)
            #expect(decodedSteps[0].params["format"]?.stringValue == "png")
            #expect(decodedSteps[1].params["degrees"]?.intValue == 90)
        } else {
            Issue.record("Expected .image body")
        }
    }

    // MARK: - ParamValue scalar decoding

    @Test("ParamValue decodes JSON scalars into the correct cases")
    func paramValueDecodesScalars() throws {
        let json = """
        {"s": "hello", "d": 1.5, "i": 7, "b": true}
        """
        let data = Data(json.utf8)
        let map = try JSONDecoder().decode([String: ParamValue].self, from: data)

        #expect(map["s"]?.stringValue == "hello")
        #expect(map["d"]?.doubleValue == 1.5)
        #expect(map["i"]?.intValue == 7)
        #expect(map["b"]?.boolValue == true)

        // Cross-accessor expectations
        #expect(map["s"]?.intValue == nil)
        #expect(map["b"]?.intValue == nil)
        #expect(map["i"]?.doubleValue == 7.0)
    }

    // MARK: - TransformBody decoding

    @Test("TransformBody decodes a js object as .text")
    func bodyDecodesText() throws {
        let data = Data(#"{"js":"return input;"}"#.utf8)
        let body = try JSONDecoder().decode(TransformBody.self, from: data)
        #expect(body == .text(js: "return input;"))
    }

    @Test("TransformBody decodes a steps object as .image")
    func bodyDecodesImage() throws {
        let data = Data(#"{"steps":[{"type":"grayscale"}]}"#.utf8)
        let body = try JSONDecoder().decode(TransformBody.self, from: data)
        #expect(body == .image(steps: [ImageStep(type: "grayscale")]))
    }

    @Test("TransformBody throws on an empty object")
    func bodyThrowsOnEmpty() {
        let data = Data("{}".utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(TransformBody.self, from: data)
        }
    }

    // MARK: - TransformBodyHash

    @Test("Identical bodies produce identical hashes")
    func sameBodySameHash() {
        let a = TransformBody.text(js: "return input.trim();")
        let b = TransformBody.text(js: "return input.trim();")
        #expect(TransformBodyHash.hash(a) == TransformBodyHash.hash(b))
    }

    @Test("Changing JS changes the hash")
    func differentJSDifferentHash() {
        let a = TransformBody.text(js: "return input.trim();")
        let b = TransformBody.text(js: "return input.trimStart();")
        #expect(TransformBodyHash.hash(a) != TransformBodyHash.hash(b))
    }

    @Test("Manifest name and version do not affect the body hash")
    func metadataDoesNotAffectBodyHash() {
        let body = TransformBody.text(js: "return input;")

        let first = TransformManifest(
            slug: "a",
            version: 1,
            kind: .text,
            name: "Alpha",
            description: "",
            icon: "x",
            category: "Case",
            body: body
        )
        let second = TransformManifest(
            slug: "b",
            version: 99,
            kind: .text,
            name: "Beta",
            description: "different",
            icon: "y",
            category: "Cleanup",
            body: body
        )

        #expect(TransformBodyHash.hash(first.body) == TransformBodyHash.hash(second.body))
    }

    @Test("Text and image bodies hash differently")
    func textVsImageHashDiffers() {
        let text = TransformBody.text(js: "[]")
        let image = TransformBody.image(steps: [])
        #expect(TransformBodyHash.hash(text) != TransformBodyHash.hash(image))
    }

    @Test("Image body hash is stable regardless of param key order")
    func imageHashStableAcrossKeyOrder() {
        let a = TransformBody.image(steps: [
            ImageStep(type: "resize", params: ["scale": .double(2), "format": .string("png")])
        ])
        let b = TransformBody.image(steps: [
            ImageStep(type: "resize", params: ["format": .string("png"), "scale": .double(2)])
        ])
        #expect(TransformBodyHash.hash(a) == TransformBodyHash.hash(b))
    }
}
