import AppKit
import Carbon

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var onboardingWindowController: OnboardingWindowController?
    private var whatsNewWindowController: WhatsNewWindowController?

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under unit tests the app is launched only to host the test bundle.
        // Skip booting the pipeline so the CloudKit-backed store is never
        // initialized in environments without iCloud provisioning.
        let isRunningTests = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isRunningTests { return }

        // Run as a menubar-only (accessory) app — no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // Migrate legacy UserDefaults history into SwiftData, then boot the pipeline.
        ClipboardMigration.runIfNeeded(context: ClipboardStore.shared.modelContextForMigration)
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

        // Show first-launch onboarding or version What's New.
        showOnboardingIfNeeded()
        showWhatsNewIfNeeded()
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

    private func showWhatsNewIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }

        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastSeen = UserDefaults.standard.string(forKey: "lastSeenVersion") ?? ""
        guard current != lastSeen else { return }

        UserDefaults.standard.set(current, forKey: "lastSeenVersion")

        let wc = WhatsNewWindowController()
        whatsNewWindowController = wc
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
