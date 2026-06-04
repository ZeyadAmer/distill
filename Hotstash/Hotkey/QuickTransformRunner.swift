import AppKit

// MARK: - QuickTransformRunner

/// Executes a quick-transform slot: reads the current clipboard text, applies the
/// slot's transform, writes the result back, and pastes it into the focused app.
@MainActor
enum QuickTransformRunner {

    static func run(slotIndex: Int) {
        let store = QuickTransformStore.shared
        guard slotIndex >= 0, slotIndex < store.slots.count else { return }
        let slot = store.slots[slotIndex]
        guard slot.isActive else { return }

        // Transforms are a Pro feature — match the panel's gating.
        guard !TrialManager.shared.isRestricted else { return }

        guard let transform = TransformRegistry.shared.orderedAll.first(where: { $0.id == slot.transformID }) else {
            return
        }

        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }

        // The target app is whatever is frontmost right now — Hotstash never
        // activated, so focus is still in the user's app.
        let targetApp = NSWorkspace.shared.frontmostApplication

        let output = transform.apply(to: text)
        PasteEngine.hotstashedCopy(output)
        AutoPasteService.paste(restoringFocusTo: targetApp)
    }
}
