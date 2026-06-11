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

    // MARK: - Item-aware API

    /// Puts a full history item on the pasteboard with every representation it
    /// was captured with (plain string + RTF + HTML, image data, or file URLs).
    /// Pass `plainTextOnly: true` to strip formatting and write just the string.
    static func hotstashedCopy(item: ClipboardItem, plainTextOnly: Bool = false) {
        ClipboardMonitor.shared.isAppWriting = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .image where item.imageData != nil:
            if let image = NSImage(data: item.imageData!) {
                pasteboard.writeObjects([image])
            }
        case .file where !item.copiedFiles.isEmpty:
            let urls = resolveFileURLs(item.copiedFiles)
            if urls.isEmpty {
                pasteboard.setString(item.content, forType: .string)
            } else {
                pasteboard.writeObjects(urls as [NSURL])
            }
        default:
            pasteboard.setString(item.content, forType: .string)
            if !plainTextOnly && !alwaysPastePlainText {
                if let rtf = item.rtfData { pasteboard.setData(rtf, forType: .rtf) }
                if let html = item.htmlData { pasteboard.setData(html, forType: .html) }
            }
        }

        ClipboardMonitor.shared.suppressCurrentChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ClipboardMonitor.shared.isAppWriting = false
        }
    }

    /// Item-aware paste: copies every representation (or plain text only),
    /// dismisses the panel, and ⌘V-pastes into the previously-focused app.
    static func hotstashedPaste(item: ClipboardItem, plainTextOnly: Bool = false) {
        hotstashedCopy(item: item, plainTextOnly: plainTextOnly)
        let target = ClipboardPanel.shared.previousApp
        ClipboardPanel.shared.dismiss()
        AutoPasteService.paste(restoringFocusTo: target)
        ReviewPrompter.shared.recordPaste()
    }

    /// User preference: always strip formatting when pasting text items.
    static var alwaysPastePlainText: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysPastePlainText") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysPastePlainText") }
    }

    // MARK: - File URL resolution

    /// Resolves stored security-scoped bookmarks back into URLs and starts
    /// access so the receiving app can read them. Falls back to raw paths for
    /// files that still exist but whose bookmark failed.
    private static func resolveFileURLs(_ files: [CopiedFile]) -> [URL] {
        files.compactMap { file in
            if let bookmark = file.bookmark {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    _ = url.startAccessingSecurityScopedResource()
                    return url
                }
            }
            let url = URL(fileURLWithPath: file.path)
            return FileManager.default.fileExists(atPath: file.path) ? url : nil
        }
    }
}
