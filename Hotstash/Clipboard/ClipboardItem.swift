import AppKit
import Foundation

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

/// An immutable value type representing a single entry in the clipboard history.
struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let content: String
    let contentType: ContentType
    let timestamp: Date

    /// Whether the item is pinned to the top of the history list.
    var isPinned: Bool

    /// Number of times the item has been pasted from the Hotstash panel.
    var useCount: Int

    /// JPEG thumbnail data for image items (nil for text items).
    var imageData: Data?

    // MARK: Designated initialiser

    init(
        id: UUID = UUID(),
        content: String,
        contentType: ContentType,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        useCount: Int = 0,
        imageData: Data? = nil
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.useCount = useCount
        self.imageData = imageData
    }

    // MARK: Equatable

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
