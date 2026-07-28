import AppKit
import CoreText
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
        // Nothing to draw into during teardown/transition snapshots.
        guard bounds.width > 0, bounds.height > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Resolve dynamic system colors against this view's appearance so the
        // recording tint and label colors match the surrounding UI.
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

            // Draw the text with CoreText directly. Going through
            // NSAttributedString.size()/draw(at:) crashed repeatedly in
            // CoreText's NSFont/NSColor conversion (TAttributes::ApplyFont →
            // "attempt to insert nil object") on macOS 26. Handing CoreText a
            // ready CTFont (toll-free bridged NSFont) and a concrete CGColor
            // bypasses that conversion entirely — identical rendering.
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            let cgColor = fg.usingColorSpace(.sRGB)?.cgColor
                ?? fg.cgColor

            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: cgColor,
            ]
            guard let attributed = CFAttributedStringCreate(
                kCFAllocatorDefault, text as CFString, attrs as CFDictionary
            ) else { return }

            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            // The view is flipped; CoreText draws in an unflipped space, so
            // flip locally around the text baseline.
            let x = (bounds.width - width) / 2
            let baselineY = (bounds.height + ascent - descent) / 2

            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: x, y: baselineY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 110, height: 26) }
}
