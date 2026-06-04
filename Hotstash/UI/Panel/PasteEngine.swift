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

    /// Puts `text` on the pasteboard, dismisses the panel, and pastes it directly
    /// into the app that was focused before Hotstash opened (when Accessibility is
    /// granted; otherwise the content is left on the pasteboard for a manual ⌘V).
    static func hotstashedPaste(_ text: String) {
        hotstashedCopy(text)
        let target = ClipboardPanel.shared.previousApp
        ClipboardPanel.shared.dismiss()
        AutoPasteService.paste(restoringFocusTo: target)
    }

    /// Puts image `data` on the pasteboard, dismisses the panel, and pastes it
    /// directly into the previously-focused app (see `hotstashedPaste`).
    static func hotstashedPasteImage(_ data: Data) {
        hotstashedCopyImage(data)
        let target = ClipboardPanel.shared.previousApp
        ClipboardPanel.shared.dismiss()
        AutoPasteService.paste(restoringFocusTo: target)
    }
}
