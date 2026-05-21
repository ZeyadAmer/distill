import AppKit
import Carbon

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Retain the registered hotkey reference for the lifetime of the app.
    private var hotKeyRef: EventHotKeyRef?

    // Retain the event handler reference so it is never released early.
    private var eventHandlerRef: EventHandlerRef?

    // Retain the onboarding window controller while it is visible.
    private var onboardingWindowController: OnboardingWindowController?

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menubar-only (accessory) app — no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Boot the clipboard pipeline.
        ClipboardMonitor.shared.start()

        // Set up the status bar item and panel.
        _ = MenuBarManager.shared
        _ = ClipboardPanel.shared

        // Register the global hotkey (CMD+Shift+V).
        registerHotkey()

        // Subscribe to the hotkey notification posted from the Carbon callback.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyNotification),
            name: .distillHotkeyPressed,
            object: nil
        )

        // Start the trial countdown and purchase listener.
        TrialManager.shared.start()
        PurchaseManager.shared.listenForTransactions()

        // Show first-launch onboarding if needed.
        showOnboardingIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running when the user closes settings or onboarding windows.
        return false
    }

    // MARK: - Hotkey handling

    @objc private func handleHotkeyNotification() {
        ClipboardPanel.shared.toggle()
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard !hasCompleted else { return }

        let wc = OnboardingWindowController()
        onboardingWindowController = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Carbon hotkey registration

    private func registerHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install a C-compatible event handler block on the application event target.
        // The block captures no state from AppDelegate to remain ABI-safe.
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                // Post the notification on the main thread.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .distillHotkeyPressed, object: nil)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            // Hotkey registration failed silently — the app still works but CMD+Shift+V won't fire.
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("DSTL"), id: 1)
        let keyCode = UInt32(kVK_ANSI_V)
        let modifiers = UInt32(cmdKey | shiftKey)

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

// MARK: - Helpers

/// Converts a four-character ASCII string literal into a FourCharCode (OSType).
func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for byte in string.utf8 {
        result = (result << 8) + FourCharCode(byte)
    }
    return result
}
