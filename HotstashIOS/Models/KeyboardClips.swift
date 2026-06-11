import Foundation

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
