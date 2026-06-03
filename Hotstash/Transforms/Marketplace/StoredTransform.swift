import Foundation
import SwiftData

/// SwiftData record persisting a marketplace transform's manifest locally.
/// The manifest JSON is stored externally; decode it via ``manifest``.
@Model
final class StoredTransform {
    var id: UUID = UUID()
    var slug: String = ""
    @Attribute(.externalStorage) var manifestJSON: Data = Data()
    var origin: String = "local"        // "local" | "installed"
    var installedVersion: Int = 0
    var isPublished: Bool = false
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), slug: String = "", manifestJSON: Data = Data(),
         origin: String = "local", installedVersion: Int = 0,
         isPublished: Bool = false, updatedAt: Date = Date.now) {
        self.id = id
        self.slug = slug
        self.manifestJSON = manifestJSON
        self.origin = origin
        self.installedVersion = installedVersion
        self.isPublished = isPublished
        self.updatedAt = updatedAt
    }

    /// Decodes the persisted manifest, or `nil` if the stored JSON is invalid.
    var manifest: TransformManifest? { try? TransformManifestCodec.decode(manifestJSON) }
}
