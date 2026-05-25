import AppKit

// MARK: - PasteEngine

/// Writes content to the system pasteboard and dismisses the panel.
/// The user presses ⌘V in their target app to complete the paste.
@MainActor
enum PasteEngine {

    // MARK: - Public API

    /// Puts `text` on the pasteboard. Panel stays open.
    static func hotstashedCopy(_ text: String) {
        ClipboardMonitor.shared.isAppWriting = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ClipboardMonitor.shared.suppressCurrentChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardMonitor.shared.isAppWriting = false
        }
    }

    /// Puts image `data` on the pasteboard. Panel stays open.
    static func hotstashedCopyImage(_ data: Data) {
        ClipboardMonitor.shared.isAppWriting = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
        ClipboardMonitor.shared.suppressCurrentChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardMonitor.shared.isAppWriting = false
        }
    }

    /// Puts `text` on the pasteboard and dismisses the panel.
    static func hotstashedPaste(_ text: String) {
        hotstashedCopy(text)
        ClipboardPanel.shared.dismiss()
    }

    /// Puts image `data` on the pasteboard and dismisses the panel.
    static func hotstashedPasteImage(_ data: Data) {
        hotstashedCopyImage(data)
        ClipboardPanel.shared.dismiss()
    }
}
