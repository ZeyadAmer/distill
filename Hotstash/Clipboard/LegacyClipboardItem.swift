import Foundation

/// Codable mirror of the pre-SwiftData `ClipboardItem` struct, used only to
/// decode the legacy UserDefaults history during one-time migration.
struct LegacyClipboardItem: Codable {
    let id: UUID
    let content: String
    let contentType: ContentType
    let timestamp: Date
    let isPinned: Bool
    let useCount: Int
    let imageData: Data?
}
