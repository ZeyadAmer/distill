import AppKit
import Carbon

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

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

        // Register the global hotkey (reads user preference, defaults to CMD+Shift+V).
        Task { @MainActor in HotkeyManager.shared.start() }

        // Subscribe to hotkey notifications posted from the Carbon callback.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyNotification),
            name: .hotstashHotkeyPressed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMultiPasteNotification),
            name: .hotstashMultiPastePressed,
            object: nil
        )

        // Start the trial countdown and purchase listener.
        TrialManager.shared.start()
        PurchaseManager.shared.listenForTransactions()

        // Show first-launch onboarding if needed.
        showOnboardingIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - Hotkey handling

    @objc private func handleHotkeyNotification() {
        Task { @MainActor in
            ClipboardPanel.shared.toggle()
        }
    }

    @objc private func handleMultiPasteNotification() {
        Task { @MainActor in
            MultiPastePanel.shared.show()
        }
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
