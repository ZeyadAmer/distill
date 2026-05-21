import AppKit
import CoreGraphics
import Foundation

// MARK: - PasteEngine

/// Writes a string to the system pasteboard and simulates CMD+V so the
/// frontmost application receives a paste event.
///
/// Callers should ensure `ClipboardMonitor.shared.isAppWriting` is not already
/// set when they call `hotstashedPaste(_:)`.
enum PasteEngine {

    // MARK: - Public API

    /// Puts `text` on the general pasteboard, hides the panel, then fires a
    /// synthetic CMD+V after a short delay that gives the previously-active
    /// window time to regain focus.
    ///
    /// - Parameter text: The string to paste into the frontmost application.
    static func hotstashedPaste(_ text: String) {
        // 1. Tell the monitor to ignore the write we are about to make.
        ClipboardMonitor.shared.isAppWriting = true

        // 2. Write to the system pasteboard.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Dismiss the panel immediately so focus can return to the caller's app.
        ClipboardPanel.shared.hide()

        // 4. Wait long enough for the panel dismiss animation to finish and for
        //    the target application's window to become key again, then post CMD+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCmdV()

            // 5. Clear the app-writing flag shortly after the keystroke so the
            //    monitor doesn't capture the content we just pasted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ClipboardMonitor.shared.isAppWriting = false
            }
        }
    }

    // MARK: - Private helpers

    /// Posts a key-down/key-up pair for the V key with the Command modifier
    /// onto the HID event tap, which causes the frontmost app to receive a
    /// standard CMD+V paste command.
    private static func postCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V

        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let up   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags   = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
