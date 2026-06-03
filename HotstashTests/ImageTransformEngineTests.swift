#if os(macOS)
import AppKit
import Testing
@testable import Hotstash

struct ImageTransformEngineTests {
    // MARK: - Helpers

    /// Render a solid-color image at exact `width` x `height` pixels and return its PNG bytes.
    /// Uses a CGContext directly so the bitmap matches the requested pixel size regardless of
    /// the display's backing scale factor (NSImage.lockFocus would render at 2x on Retina).
    private func makeImagePNG(width: Int, height: Int, color: NSColor = .systemBlue) -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to build test context")
        }
        let rgb = color.usingColorSpace(.sRGB) ?? color
        context.setFillColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            fatalError("Failed to build test image")
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to encode test PNG")
        }
        return data
    }

    /// Decode image bytes to pixel dimensions.
    private func dimensions(of data: Data) -> (width: Int, height: Int)? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return (cgImage.width, cgImage.height)
    }

    private let tolerance = 1

    private func approxEqual(_ value: Int, _ expected: Int) -> Bool {
        abs(value - expected) <= tolerance
    }

    // MARK: - Tests

    @Test("resize scale 0.5 halves dimensions")
    func resizeScaleShrinksDimensions() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [ImageStep(type: "resize", params: ["scale": .double(0.5)])]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 50))
        #expect(approxEqual(dims?.height ?? -1, 30))
    }

    @Test("resize maxDim caps the longest side and preserves aspect")
    func resizeMaxDim() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [ImageStep(type: "resize", params: ["maxDim": .int(50)])]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 50))
        #expect(approxEqual(dims?.height ?? -1, 30))
    }

    @Test("grayscale produces a valid image of the same dimensions")
    func grayscaleProducesValidImage() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [ImageStep(type: "grayscale")]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 100))
        #expect(approxEqual(dims?.height ?? -1, 60))
    }

    @Test("rotate 90 swaps dimensions")
    func rotate90SwapsDimensions() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [ImageStep(type: "rotate", params: ["degrees": .int(90)])]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 60))
        #expect(approxEqual(dims?.height ?? -1, 100))
    }

    @Test("unknown step is skipped, dimensions unchanged")
    func unknownStepSkipped() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [ImageStep(type: "bogus")]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 100))
        #expect(approxEqual(dims?.height ?? -1, 60))
    }

    @Test("empty steps returns original data byte-for-byte")
    func emptySteps() {
        let input = makeImagePNG(width: 100, height: 60)
        let result = ImageTransformEngine.run(steps: [], imageData: input)
        #expect(result == input)
    }

    @Test("invalid rotate degrees are skipped, dimensions unchanged")
    func invalidRotateDegreesSkipped() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [ImageStep(type: "rotate", params: ["degrees": .int(45)])]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 100))
        #expect(approxEqual(dims?.height ?? -1, 60))
    }

    @Test("chained resize then rotate composes in order")
    func chainedSteps() {
        let input = makeImagePNG(width: 100, height: 60)
        let steps = [
            ImageStep(type: "resize", params: ["scale": .double(0.5)]), // → 50x30
            ImageStep(type: "rotate", params: ["degrees": .int(90)])     // → 30x50
        ]
        let result = ImageTransformEngine.run(steps: steps, imageData: input)

        let dims = dimensions(of: result)
        #expect(dims != nil)
        #expect(approxEqual(dims?.width ?? -1, 30))
        #expect(approxEqual(dims?.height ?? -1, 50))
    }
}
#endif
