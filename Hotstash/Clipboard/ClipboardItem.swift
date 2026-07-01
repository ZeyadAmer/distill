import Foundation
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

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
        case .file:      return "File"
        case .plainText: return "Text"
        }
    }
}

#if canImport(AppKit)
extension ContentType {
    /// Badge background colour used in the clipboard panel row.
    /// All colours are semantic/system colours so they adapt to light/dark mode automatically.
    var badgeColor: NSColor {
        switch self {
        case .json:      return NSColor.systemOrange
        case .url:       return NSColor.systemBlue
        case .code:      return NSColor.systemPurple
        case .list:      return NSColor.systemGreen
        case .image:     return NSColor.systemTeal
        case .file:      return NSColor.systemBrown
        case .plainText: return NSColor.secondaryLabelColor
        }
    }
}
#endif

// MARK: - CopiedFile

/// One file reference captured from a Finder copy. The security-scoped
/// bookmark lets the sandboxed app re-provide the file URL across launches.
struct CopiedFile: Codable {
    let name: String
    let path: String
    let bookmark: Data?
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
    /// RTF representation captured alongside `content`, preserved for rich paste.
    @Attribute(.externalStorage) var rtfData: Data?
    /// HTML representation captured alongside `content`, preserved for rich paste.
    @Attribute(.externalStorage) var htmlData: Data?
    /// JSON-encoded `[CopiedFile]` when this item is a Finder file copy.
    @Attribute(.externalStorage) var fileInfoData: Data?
    /// Text recognized inside `imageData` via Vision OCR. Searchable; empty when none.
    var ocrText: String = ""
    /// Page title fetched for URL items via LinkPresentation. Empty when none.
    var linkTitle: String = ""
    /// User-assigned name for quick search (e.g. "supabase"). Searchable; empty when none.
    var label: String = ""
    /// The `Folder` this item is stored in, or nil when it lives in Recents/Pinned.
    var folderID: UUID?

    /// Typed accessor over the persisted raw string.
    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .plainText }
        set { contentTypeRaw = newValue.rawValue }
    }

    /// Decoded file references for `.file` items.
    var copiedFiles: [CopiedFile] {
        guard let data = fileInfoData else { return [] }
        return (try? JSONDecoder().decode([CopiedFile].self, from: data)) ?? []
    }

    init(
        id: UUID = UUID(),
        content: String,
        contentType: ContentType,
        timestamp: Date = .now,
        isPinned: Bool = false,
        pinnedOrder: Int = 0,
        useCount: Int = 0,
        imageData: Data? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        fileInfoData: Data? = nil,
        ocrText: String = "",
        linkTitle: String = "",
        label: String = "",
        folderID: UUID? = nil
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
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.fileInfoData = fileInfoData
        self.ocrText = ocrText
        self.linkTitle = linkTitle
        self.label = label
        self.folderID = folderID
    }
}
