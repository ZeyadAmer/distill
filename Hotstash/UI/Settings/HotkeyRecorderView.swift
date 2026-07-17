import AppKit
import SwiftUI

// MARK: - HotkeyRecorderView

/// SwiftUI wrapper around `HotkeyRecorderControl`.
/// Binds to a `(keyCode, modifiers)` pair stored in `HotkeyManager`.
struct HotkeyRecorderView: NSViewRepresentable {

    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    /// Applies the new shortcut. Defaults to the main hotkey; pass
    /// `HotkeyManager.shared.updateMultiPaste` for the multi-paste shortcut.
    var commit: ((UInt32, UInt32) -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl()
        control.onCommit = { newCode, newMods in
            keyCode   = newCode
            modifiers = newMods
            if let commit {
                commit(newCode, newMods)
            } else {
                HotkeyManager.shared.update(keyCode: newCode, modifiers: newMods)
            }
        }
        return control
    }

    func updateNSView(_ control: HotkeyRecorderControl, context: Context) {
        control.displayString = HotkeyManager.displayString(
            keyCode: keyCode,
            carbonModifiers: modifiers
        )
    }
}

// MARK: - HotkeyRecorderControl

/// An NSControl that shows the current shortcut and captures a new one on click.
final class HotkeyRecorderControl: NSControl {

    var displayString: String = "" { didSet { needsDisplay = true } }
    var onCommit: ((UInt32, UInt32) -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Escape cancels recording without changing the shortcut.
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            window?.makeFirstResponder(nil)
            return
        }

        // Require at least one modifier key.
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else { return }

        let carbonMods = HotkeyManager.carbonModifiers(from: flags)
        let code       = UInt32(event.keyCode)

        isRecording = false
        needsDisplay = true
        window?.makeFirstResponder(nil)
        onCommit?(code, carbonMods)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Nothing to draw into during teardown/transition snapshots — bail before
        // touching CoreText, which throws if dynamic colors resolve without context.
        guard bounds.width > 0, bounds.height > 0, NSGraphicsContext.current != nil else { return }

        // Resolve dynamic system colors against this view's appearance. Without an
        // explicit drawing appearance (as happens mid-TabView transition), CoreText
        // can insert a nil into its attribute dictionary and abort. See crash logs
        // for HotkeyRecorderControl.draw (SIGABRT in TAttributes::ApplyFont).
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let text  = isRecording ? "Press shortcut…" : displayString
            let bg    = isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : NSColor.controlBackgroundColor
            let border: NSColor = isRecording ? .controlAccentColor : .separatorColor
            let fg: NSColor     = isRecording ? .controlAccentColor : .labelColor

            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            bg.setFill(); path.fill()
            border.setStroke(); path.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: fg,
            ]
            let attributed = NSAttributedString(string: text, attributes: attrs)
            let sz = attributed.size()
            let origin = NSPoint(
                x: (bounds.width  - sz.width)  / 2,
                y: (bounds.height - sz.height) / 2
            )
            attributed.draw(at: origin)
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 110, height: 26) }
}
