#if os(macOS)
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Interprets a declarative, ordered pipeline of whitelisted native image steps.
///
/// This engine carries NO arbitrary code. Each `ImageStep.type` maps to a fixed,
/// reviewed native operation. The engine never crashes:
/// - Unknown step types are skipped (data passed through unchanged).
/// - A step that fails (bad params, decode failure) is skipped; the last-good data is kept.
/// - If everything fails, the original `imageData` is returned unchanged.
enum ImageTransformEngine {
    // MARK: - Public API

    /// Apply each step in order to `imageData`, returning the transformed image bytes.
    /// Returns the original `imageData` if no step produces usable output.
    static func run(steps: [ImageStep], imageData: Data) -> Data {
        var current = imageData
        for step in steps {
            // A failed/unknown step leaves `current` untouched and we move on.
            if let next = apply(step: step, to: current) {
                current = next
            }
        }
        return current
    }

    // MARK: - Step Dispatch

    /// Returns transformed data for a single step, or `nil` to skip (keep last-good data).
    private static func apply(step: ImageStep, to data: Data) -> Data? {
        switch step.type {
        case "resize":          return resize(step: step, data: data)
        case "grayscale":       return grayscale(data: data)
        case "rotate":          return rotate(step: step, data: data)
        case "flipHorizontal":  return flipHorizontal(data: data)
        case "convertPNG":      return encodePNG(data: data)
        case "convertWebP":     return encodeWebP(data: data)
        default:                return nil // Unknown step type → skip.
        }
    }

    // MARK: - Resize

    private static func resize(step: ImageStep, data: Data) -> Data? {
        guard let cgImage = decode(data) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        // Resolve target dimensions from either `scale` or `maxDim`.
        let target: (width: Int, height: Int)
        if let rawScale = step.params["scale"]?.doubleValue, rawScale > 0 {
            // Cap scale to mirror the server's validation (<= 10) so a manifest
            // can't blow up memory with an enormous upscale.
            let scale = min(rawScale, 10.0)
            target = (
                max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded()))
            )
        } else if let maxDim = step.params["maxDim"]?.intValue, maxDim > 0 {
            let longest = max(width, height)
            // Don't upscale: only shrink when the longest side exceeds maxDim.
            let factor = longest > maxDim ? Double(maxDim) / Double(longest) : 1.0
            target = (
                max(1, Int((Double(width) * factor).rounded())),
                max(1, Int((Double(height) * factor).rounded()))
            )
        } else {
            return nil // Missing/invalid resize param → skip.
        }

        guard let resized = render(cgImage, width: target.width, height: target.height) else { return nil }
        return encode(resized)
    }

    // MARK: - Grayscale

    private static func grayscale(data: Data) -> Data? {
        guard let ciImage = CIImage(data: data),
              let filter = CIFilter(name: "CIColorMonochrome") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIColor.white, forKey: kCIInputColorKey)
        filter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let output = filter.outputImage,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return encode(cgImage)
    }

    // MARK: - Rotate

    private static func rotate(step: ImageStep, data: Data) -> Data? {
        guard let degrees = step.params["degrees"]?.intValue,
              degrees == 90 || degrees == 180 || degrees == 270,
              let cgImage = decode(data) else { return nil }

        let orientation: CGImagePropertyOrientation
        switch degrees {
        case 90:  orientation = .right // 90° clockwise
        case 180: orientation = .down
        default:  orientation = .left  // 270° clockwise
        }

        let oriented = CIImage(cgImage: cgImage).oriented(orientation)
        guard let result = ciContext.createCGImage(oriented, from: oriented.extent) else { return nil }
        return encode(result)
    }

    // MARK: - Flip Horizontal

    private static func flipHorizontal(data: Data) -> Data? {
        guard let cgImage = decode(data) else { return nil }
        let mirrored = CIImage(cgImage: cgImage).oriented(.upMirrored)
        guard let result = ciContext.createCGImage(mirrored, from: mirrored.extent) else { return nil }
        return encode(result)
    }

    // MARK: - Encoders

    private static func encodePNG(data: Data) -> Data? {
        guard let cgImage = decode(data) else { return nil }
        return encode(cgImage)
    }

    private static func encodeWebP(data: Data) -> Data? {
        guard let cgImage = decode(data) else { return nil }
        let output = NSMutableData()
        let type: CFString
        if #available(macOS 11.0, *) {
            type = UTType.webP.identifier as CFString
        } else {
            type = "public.webp" as CFString
        }
        guard let dest = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            return data // WebP unavailable on this system → leave data unchanged for this step.
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            return data // Encoding unsupported → leave data unchanged.
        }
        return output as Data
    }

    // MARK: - Image Helpers

    private static let ciContext = CIContext()

    /// Decode image bytes to a `CGImage` (handles PNG, TIFF, WebP, etc. via NSImage).
    private static func decode(_ data: Data) -> CGImage? {
        guard let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Encode a `CGImage` to PNG bytes — the engine's canonical intermediate format.
    private static func encode(_ cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    /// Render `cgImage` into a new bitmap of exact pixel dimensions.
    private static func render(_ cgImage: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
#endif
