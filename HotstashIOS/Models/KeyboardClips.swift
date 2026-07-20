import Foundation
import UIKit

// MARK: - KeyboardClip

/// One clipboard entry mirrored into the app-group defaults for the keyboard
/// extension. Text-only — image and file items are never mirrored.
struct KeyboardClip: Codable, Identifiable, Equatable {
    let id: UUID
    let content: String
    let contentTypeRaw: String
    let isPinned: Bool
}

// MARK: - KeyboardClipsMirror

/// JSON mirror of the latest text clips, written by the main app (and the
/// share extension) and read by the keyboard extension. This mirror is the
/// keyboard's ONLY data source — the keyboard never opens the SwiftData store.
enum KeyboardClipsMirror {

    static let maxClips = 50
    private static let key = "ios.keyboardClips"

    static func write(_ clips: [KeyboardClip]) {
        guard let data = try? JSONEncoder().encode(Array(clips.prefix(maxClips))) else { return }
        SharedDefaults.store.set(data, forKey: key)
    }

    static func read() -> [KeyboardClip] {
        guard
            let data  = SharedDefaults.store.data(forKey: key),
            let clips = try? JSONDecoder().decode([KeyboardClip].self, from: data)
        else { return [] }
        return clips
    }

    /// Inserts a clip at the front of the mirror (dropping any older clip with
    /// identical content). Used by the share extension, which can't refresh
    /// the full list cheaply.
    static func prepend(_ clip: KeyboardClip) {
        var clips = read()
        clips.removeAll { $0.content == clip.content }
        clips.insert(clip, at: 0)
        write(clips)
    }
}

// MARK: - PendingImports

/// Texts captured by the keyboard extension that the main app hasn't turned
/// into real `ClipboardItem` records yet. The app drains this on foreground,
/// inserting into the SwiftData store (which then syncs to the Mac).
enum PendingImports {

    private static let key = "ios.pendingImports"
    private static let maxPending = 50

    static func add(_ text: String) {
        var current = SharedDefaults.store.stringArray(forKey: key) ?? []
        current.removeAll { $0 == text }
        current.append(text)
        SharedDefaults.store.set(Array(current.suffix(maxPending)), forKey: key)
    }

    /// Returns all queued texts (oldest first) and clears the queue.
    static func drain() -> [String] {
        let current = SharedDefaults.store.stringArray(forKey: key) ?? []
        SharedDefaults.store.removeObject(forKey: key)
        return current
    }
}

// MARK: - KeyboardCapture

/// Lets the keyboard extension capture whatever is on the system pasteboard
/// the moment the keyboard opens — the closest iOS allows to automatic
/// capture (no app can read the clipboard in the background).
enum KeyboardCapture {

    private static let changeCountKey = "ios.keyboardSeenChangeCount"

    /// Captures the current pasteboard string when it changed since the last
    /// look: queues it for the app to import and surfaces it in the mirror
    /// immediately so it shows in the keyboard right away.
    @discardableResult
    static func captureIfNew() -> Bool {
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount

        // First run (key unset): seed the baseline instead of capturing, so
        // whatever happened to be on the pasteboard before the keyboard was
        // ever opened — possibly a password or OTP from another app — is NOT
        // silently swept into permanent, cross-device history.
        guard SharedDefaults.store.object(forKey: changeCountKey) != nil else {
            SharedDefaults.store.set(count, forKey: changeCountKey)
            return false
        }
        guard count != SharedDefaults.store.integer(forKey: changeCountKey) else { return false }
        SharedDefaults.store.set(count, forKey: changeCountKey)

        guard let text = pasteboard.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        PendingImports.add(text)
        KeyboardClipsMirror.prepend(KeyboardClip(
            id: UUID(),
            content: text,
            contentTypeRaw: ContentDetector.detect(text).rawValue,
            isPinned: false
        ))
        return true
    }
}
