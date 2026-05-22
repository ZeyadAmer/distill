import AppKit

// MARK: - PasteEngine

/// Writes content to the system pasteboard and dismisses the panel.
/// The user presses ⌘V in their target app to complete the paste.
@MainActor
enum PasteEngine {

    // MARK: - Public API

    /// Puts `text` on the general pasteboard and dismisses the panel.
    static func hotstashedPaste(_ text: String) {
        ClipboardMonitor.shared.isAppWriting = true

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        ClipboardPanel.shared.dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardMonitor.shared.isAppWriting = false
        }
    }

    /// Puts image `data` on the pasteboard and dismisses the panel.
    static func hotstashedPasteImage(_ data: Data) {
        ClipboardMonitor.shared.isAppWriting = true

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }

        ClipboardPanel.shared.dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardMonitor.shared.isAppWriting = false
        }
    }
}
