import AppKit
import Foundation
import SwiftData

// ContentType is defined in Transforms/ContentDetector.swift.
// This extension adds UI-facing computed properties.
extension ContentType {

    /// Human-readable label shown in the UI.
    var displayName: String {
        switch self {
        case .json:      return "JSON"
        case .url:       return "URL"
        case .code:      return "Code"
        case .list:      return "List"
        case .image:     return "Image"
        case .plainText: return "Text"
        }
    }

    /// Badge background colour used in the clipboard panel row.
    /// All colours are semantic/system colours so they adapt to light/dark mode automatically.
    var badgeColor: NSColor {
        switch self {
        case .json:      return NSColor.systemOrange
        case .url:       return NSColor.systemBlue
        case .code:      return NSColor.systemPurple
        case .list:      return NSColor.systemGreen
        case .image:     return NSColor.systemTeal
        case .plainText: return NSColor.secondaryLabelColor
        }
    }
}

// MARK: - ClipboardItem

/// A single entry in the clipboard history, persisted by SwiftData and
/// mirrored to the user's private CloudKit database.
///
/// CloudKit constraints: every stored property has a default value and there
/// are no unique constraints. Uniqueness by `id` is enforced in `ClipboardStore`.
@Model
final class ClipboardItem {
    var id: UUID = UUID()
    var content: String = ""
    var contentTypeRaw: String = ContentType.plainText.rawValue
    var timestamp: Date = Date.now
    var isPinned: Bool = false
    /// Stable ordering among pinned items (lower = higher in the pinned list).
    var pinnedOrder: Int = 0
    var useCount: Int = 0
    @Attribute(.externalStorage) var imageData: Data?
    /// True when `imageData` is present. Sentinel so image queries avoid
    /// nil-comparison predicates (CloudKit-safe).
    var hasImage: Bool = false

    /// Typed accessor over the persisted raw string.
    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .plainText }
        set { contentTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        content: String,
        contentType: ContentType,
        timestamp: Date = .now,
        isPinned: Bool = false,
        pinnedOrder: Int = 0,
        useCount: Int = 0,
        imageData: Data? = nil
    ) {
        self.id = id
        self.content = content
        self.contentTypeRaw = contentType.rawValue
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.pinnedOrder = pinnedOrder
        self.useCount = useCount
        self.imageData = imageData
        self.hasImage = imageData != nil
    }
}
