import Foundation
import OSLog
import SwiftUI

// MARK: - QuickTransformSlot

/// A user-configurable mapping: a global hotkey → a transform applied to the
/// current clipboard contents, then pasted straight into the focused app.
struct QuickTransformSlot: Codable, Equatable, Identifiable {

    /// Stable 0-based slot index (also drives the Carbon hotkey id).
    let id: Int

    /// Carbon key code. `0` means no key has been recorded yet.
    var keyCode: UInt32

    /// Carbon modifier bitmask.
    var modifiers: UInt32

    /// The transform applied when this shortcut fires.
    var transformID: String

    /// Whether the user has switched this slot on.
    var isEnabled: Bool

    /// A slot only registers a hotkey when enabled with a recorded key and transform.
    var isActive: Bool {
        isEnabled && keyCode != 0 && !transformID.isEmpty
    }
}

// MARK: - QuickTransformStore

/// Persists the five quick-transform slots and keeps the global hotkeys in sync.
@MainActor
final class QuickTransformStore: ObservableObject {

    static let shared = QuickTransformStore()

    static let slotCount = 5

    private let defaultsKey = "quickTransformSlots"

    /// Default transform ids, applied the first time the slots are created.
    /// Slots ship disabled with no key recorded — nothing is registered until
    /// the user opts in.
    private static let defaultTransformIDs = [
        "to_uppercase",
        "to_lowercase",
        "trim_whitespace",
        "format_json",
        "base64_encode",
    ]

    @Published private(set) var slots: [QuickTransformSlot]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([QuickTransformSlot].self, from: data),
           decoded.count == Self.slotCount {
            slots = decoded
        } else {
            slots = (0 ..< Self.slotCount).map { index in
                QuickTransformSlot(
                    id: index,
                    keyCode: 0,
                    modifiers: 0,
                    transformID: Self.defaultTransformIDs[index],
                    isEnabled: false
                )
            }
        }
    }

    /// Replaces one slot, persists, and re-registers the global hotkeys.
    func update(_ slot: QuickTransformSlot) {
        guard slot.id >= 0, slot.id < slots.count else { return }
        slots[slot.id] = slot
        persist()
        HotkeyManager.shared.registerQuickTransforms()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(slots)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // Encoding a small [QuickTransformSlot] shouldn't fail, but if it
            // does the config silently reverts on next launch — at least log it.
            Logger(subsystem: "com.zeyadamer.hotstash", category: "QuickTransformStore")
                .error("Failed to persist quick-transform slots: \(error, privacy: .public)")
        }
    }
}
