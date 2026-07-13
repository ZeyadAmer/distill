import SwiftUI

/// Renders a transform icon from its single `icon` string, which may be:
///   - a base64 PNG data URI (`data:image/png;base64,…`) → decoded image
///   - an emoji (`🔥`) → drawn as text
///   - anything else → treated as an SF Symbol name
///
/// One view so every surface (Marketplace, Settings, iOS rows) renders all
/// three kinds identically. Callers keep applying `.frame`/`.foregroundStyle`
/// as before; image icons scale to fit the frame, glyphs inherit the font.
struct TransformIconView: View {
    let icon: String

    var body: some View {
        if let image = Self.decodeDataURI(icon) {
            image.resizable().scaledToFit()
        } else if Self.isEmoji(icon) {
            Text(icon)
        } else {
            Image(systemName: icon)
        }
    }

    // MARK: - Classification

    /// data URIs are the only icons that start with "data:"; SF Symbol names
    /// are ASCII identifiers, so a leading emoji scalar disambiguates the rest.
    static func isEmoji(_ string: String) -> Bool {
        guard let scalar = string.unicodeScalars.first else { return false }
        // `isEmoji` is true for plain digits/`#`/`*` too, so require either an
        // emoji-presentation default or a codepoint above the ASCII symbol range.
        return scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && scalar.value > 0x2600)
    }

    static func decodeDataURI(_ string: String) -> Image? {
        guard string.hasPrefix("data:image"),
              let comma = string.firstIndex(of: ","),
              let data = Data(base64Encoded: String(string[string.index(after: comma)...]))
        else { return nil }
        #if canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #elseif canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}

// ponytail: 64×64 PNG cap is enforced at authoring time (TransformBuilderView),
// so decode stays trivial — no size guard needed on the read path.
