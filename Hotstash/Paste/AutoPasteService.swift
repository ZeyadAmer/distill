import AppKit
import ApplicationServices

// MARK: - AssistivePasteService

/// **Assistive Paste** — an accessibility accommodation for people who have
/// difficulty performing the ⌘V keyboard shortcut (e.g. motor or dexterity
/// impairments). When the user turns it on, Hotstash inserts the selected item
/// directly instead of requiring them to press ⌘V.
///
/// This is the app's **only** use of the macOS Accessibility API, and it exists
/// solely to increase accessibility. It is **off by default** and opt-in from
/// Settings → Accessibility. When disabled — the default — the item is simply
/// placed on the pasteboard and the user pastes with ⌘V; no Accessibility
/// permission is requested or used.
@MainActor
enum AutoPasteService {

    /// UserDefaults key for the opt-in accommodation toggle.
    private static let enabledKey = "assistivePasteEnabled"

    /// Physical key code for the "V" key on a US layout (kVK_ANSI_V).
    private static let vKeyCode: CGKeyCode = 9

    /// When the last synthetic ⌘V was posted. PasteStackManager uses this to
    /// ignore the app's own keystrokes in its event tap.
    private(set) static var lastSyntheticPaste: Date = .distantPast

    /// Delay before posting ⌘V when we first reactivate another app — gives the
    /// window server time to move key focus back to the target app.
    private static let focusRestoreDelay: TimeInterval = 0.12

    // MARK: - Opt-in state

    /// Whether the user has turned on the Assistive Paste accommodation.
    /// Off by default — the app never inserts keystrokes unless a user opts in.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Whether the process is currently trusted for Accessibility. Silent check —
    /// never prompts.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility permission (system dialog). Called only when the
    /// user explicitly enables the accommodation from Settings → Accessibility.
    @discardableResult
    static func requestPermission() -> Bool {
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

    /// Reactivates `app` (when supplied) and inserts the pasteboard item for the
    /// user. No-op unless the user has opted into Assistive Paste and granted
    /// Accessibility — otherwise the content stays on the pasteboard for a
    /// manual ⌘V.
    static func paste(restoringFocusTo app: NSRunningApplication?) {
        guard isEnabled, isTrusted else { return }

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
