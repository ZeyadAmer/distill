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

    private enum Keys {
        static let didRequestPermission = "didRequestAccessibilityPermission"
    }

    /// Physical key code for the "V" key on a US layout (kVK_ANSI_V).
    private static let vKeyCode: CGKeyCode = 9

    /// Delay before posting ⌘V when we first reactivate another app — gives the
    /// window server time to move key focus back to the target app.
    private static let focusRestoreDelay: TimeInterval = 0.12

    // MARK: - Permission

    /// Whether the process is currently trusted for Accessibility.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility permission (system dialog), once. Subsequent
    /// calls re-check trust without prompting again.
    @discardableResult
    static func requestPermissionIfNeeded() -> Bool {
        if isTrusted { return true }
        let alreadyAsked = UserDefaults.standard.bool(forKey: Keys.didRequestPermission)
        guard !alreadyAsked else { return false }
        UserDefaults.standard.set(true, forKey: Keys.didRequestPermission)
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
    /// When Accessibility is not yet granted, this requests it once and returns
    /// without pasting (the content remains on the pasteboard for a manual ⌘V).
    static func paste(restoringFocusTo app: NSRunningApplication?) {
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
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
