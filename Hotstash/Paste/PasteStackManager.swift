import AppKit

// MARK: - PasteStackManager

/// Sequential paste queue ("paste stack").
///
/// **Retired.** The feature relied on a system-wide CGEvent tap to watch for
/// the user's ⌘V keystrokes — a use of the Accessibility API unrelated to
/// increasing accessibility, which is not permitted on the App Store. The tap
/// has been removed; the app's only Accessibility use is now the opt-in
/// Assistive Paste accommodation (`AutoPasteService`).
///
/// This inert stub is kept so existing call sites compile; `start` always
/// reports the feature as unavailable and no stack is ever active.
@MainActor
final class PasteStackManager {

    static let shared = PasteStackManager()
    private init() {}

    private(set) var queue: [ClipboardItem] = []
    private(set) var nextIndex: Int = 0

    var isActive: Bool { false }
    var remainingCount: Int { 0 }

    /// No-op: the paste stack has been retired (see type doc).
    @discardableResult
    func start(items: [ClipboardItem]) -> Bool { false }

    func stop() {}
}

// MARK: - Notification

extension Notification.Name {
    /// Posted whenever the paste stack starts, advances, or finishes.
    static let pasteStackChanged = Notification.Name("pasteStackChanged")
}
