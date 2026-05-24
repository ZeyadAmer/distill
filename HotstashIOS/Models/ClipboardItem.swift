import Foundation

// ContentType is defined in Hotstash/Transforms/ContentDetector.swift (shared source).

extension ContentType {
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
}

// MARK: - ClipboardItem

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let content: String
    let contentType: ContentType
    let timestamp: Date
    var isPinned: Bool
    var useCount: Int

    init(
        id: UUID = UUID(),
        content: String,
        contentType: ContentType,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        useCount: Int = 0
    ) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.useCount = useCount
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}
