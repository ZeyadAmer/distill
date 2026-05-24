import Foundation

enum SharedDefaults {
    static let suiteName = "group.com.zeyadamer.hotstash"

    static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    enum Keys {
        static let clipboardHistory = "ios.clipboardHistory"
        static let snippets         = "ios.snippets"
        static let multiPasteQueue  = "ios.multiPasteQueue"
    }
}
