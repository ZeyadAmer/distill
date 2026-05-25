#if os(macOS)
import AppKit
import CoreImage

// MARK: - Shared helper

private func renderTIFF(_ ciImage: CIImage) -> Data? {
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .tiff, properties: [:])
}

// MARK: - ResizeHalfTransform

struct ResizeHalfTransform: Transform {
    let id       = "image_resize_half"
    let name     = "Resize to 50%"
    let icon     = "arrow.down.right.and.arrow.up.left"
    let category = TransformCategory.image
    let applicableTo: [ContentType] = [.image]

    func apply(to input: String) -> String { input }

    func applyToImageData(_ data: Data) -> Data? {
        guard let ciImage = CIImage(data: data) else { return nil }
        let scale = CGAffineTransform(scaleX: 0.5, y: 0.5)
        return renderTIFF(ciImage.transformed(by: scale))
    }
}

// MARK: - GrayscaleTransform

struct GrayscaleTransform: Transform {
    let id       = "image_grayscale"
    let name     = "Grayscale"
    let icon     = "circle.lefthalf.filled"
    let category = TransformCategory.image
    let applicableTo: [ContentType] = [.image]

    func apply(to input: String) -> String { input }

    func applyToImageData(_ data: Data) -> Data? {
        guard let ciImage = CIImage(data: data),
              let filter = CIFilter(name: "CIColorMonochrome") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIColor.white, forKey: kCIInputColorKey)
        filter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let output = filter.outputImage else { return nil }
        return renderTIFF(output)
    }
}

// MARK: - ConvertToPNGTransform

struct ConvertToPNGTransform: Transform {
    let id       = "image_to_png"
    let name     = "Convert to PNG"
    let icon     = "doc.badge.arrow.up"
    let category = TransformCategory.image
    let applicableTo: [ContentType] = [.image]

    func apply(to input: String) -> String { input }

    func applyToImageData(_ data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - ConvertToWebPTransform

struct ConvertToWebPTransform: Transform {
    let id       = "image_to_webp"
    let name     = "Convert to WebP"
    let icon     = "doc.badge.arrow.up"
    let category = TransformCategory.image
    let applicableTo: [ContentType] = [.image]

    func apply(to input: String) -> String { input }

    func applyToImageData(_ data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.webp" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return output as Data
    }
}

// MARK: - FlipHorizontalTransform

struct FlipHorizontalTransform: Transform {
    let id       = "image_flip_horizontal"
    let name     = "Flip Horizontal"
    let icon     = "arrow.left.and.right.righttriangle.left.righttriangle.right"
    let category = TransformCategory.image
    let applicableTo: [ContentType] = [.image]

    func apply(to input: String) -> String { input }

    func applyToImageData(_ data: Data) -> Data? {
        guard let ciImage = CIImage(data: data) else { return nil }
        return renderTIFF(ciImage.oriented(.upMirrored))
    }
}

// MARK: - Rotate90Transform

struct Rotate90Transform: Transform {
    let id       = "image_rotate_90"
    let name     = "Rotate 90° Clockwise"
    let icon     = "rotate.right"
    let category = TransformCategory.image
    let applicableTo: [ContentType] = [.image]

    func apply(to input: String) -> String { input }

    func applyToImageData(_ data: Data) -> Data? {
        guard let ciImage = CIImage(data: data) else { return nil }
        return renderTIFF(ciImage.oriented(.right))
    }
}
#endif
