import AppKit
import ApplicationServices

// MARK: - AutoPasteService

/// Synthesizes a ⌘V keystroke into the previously-focused application so an item
/// can be pasted directly, without the user pressing ⌘V themselves.
///
/// This requires macOS **Accessibility** permission (System Settings → Privacy &
/// Security → Accessibility). When permission is missing the service silently
/// degrades to copy-only behaviour: the content is already on the pasteboard, so
/// the user can still paste manually.
@MainActor
enum AutoPasteService {

    /// Physical key code for the "V" key on a US layout (kVK_ANSI_V).
    private static let vKeyCode: CGKeyCode = 9

    /// When the last synthetic ⌘V was posted. PasteStackManager uses this to
    /// ignore the app's own keystrokes in its event tap.
    private(set) static var lastSyntheticPaste: Date = .distantPast

    /// Delay before posting ⌘V when we first reactivate another app — gives the
    /// window server time to move key focus back to the target app.
    private static let focusRestoreDelay: TimeInterval = 0.12

    // MARK: - Permission

    /// Whether the process is currently trusted for Accessibility. Silent check —
    /// never prompts, never adds the app to the Accessibility list.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility permission (system dialog), once. Gated behind
    /// the `directPasteEnabled` remote flag so the prompt never appears unless
    /// the server has turned the feature on. Returns current trust otherwise.
    @discardableResult
    static func requestPermissionIfNeeded() -> Bool {
        guard RemoteFlags.directPasteEnabled else { return isTrusted }
        if isTrusted { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens the Accessibility pane of System Settings.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Paste

    /// Reactivates `app` (when supplied) and synthesizes ⌘V into it.
    ///
    /// When Accessibility is not granted, this prompts once (only if the remote
    /// flag is on) and returns — the content is already on the pasteboard for a
    /// manual ⌘V. With the flag off it never prompts.
    static func paste(restoringFocusTo app: NSRunningApplication?) {
        // Master switch: with the flag off the feature is fully dormant — no
        // paste, no prompt — even for users who granted access in an older build.
        guard RemoteFlags.directPasteEnabled else { return }
        guard isTrusted else {
            requestPermissionIfNeeded()
            return
        }

        let needsFocusRestore = app != nil
            && app?.processIdentifier != ProcessInfo.processInfo.processIdentifier

        if needsFocusRestore {
            app?.activate()
        }

        let delay = needsFocusRestore ? focusRestoreDelay : 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            postCommandV()
        }
    }

    // MARK: - Private

    private static func postCommandV() {
        lastSyntheticPaste = .now
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
