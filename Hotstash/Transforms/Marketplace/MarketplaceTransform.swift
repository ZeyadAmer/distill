import Foundation

/// Adapts a marketplace `TransformManifest` to the app's `Transform` protocol so
/// custom/installed transforms slot into `TransformRegistry` alongside built-ins.
struct MarketplaceTransform: Transform {
    let manifest: TransformManifest

    var id: String { manifest.slug }
    var name: String { manifest.name }
    var icon: String { manifest.icon }
    var category: TransformCategory { TransformCategory(rawValue: manifest.category) ?? .cleanup }
    var applicableTo: [ContentType] { manifest.kind == .image ? [.image] : [] }

    func apply(to input: String) -> String {
        guard case let .text(js) = manifest.body else { return input }
        // The engine returns the original input unchanged on any failure.
        return TextTransformEngine.run(js: js, input: input).output
    }

    func applyToImageData(_ data: Data) -> Data? {
        guard case let .image(steps) = manifest.body else { return nil }
        return ImageTransformEngine.run(steps: steps, imageData: data)
    }
}
