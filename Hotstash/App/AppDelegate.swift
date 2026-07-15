import AppKit
import Carbon

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var onboardingWindowController: OnboardingWindowController?
    private var whatsNewWindowController: WhatsNewWindowController?
    private var signInPromptWindowController: SignInPromptWindowController?

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

        // Install the main menu so standard editing shortcuts (⌘X/⌘C/⌘V/⌘A,
        // ⌘Z) work in Settings/marketplace text fields.
        AppMenu.install()

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickTransformNotification(_:)),
            name: .hotstashQuickTransform,
            object: nil
        )

        // Register the URL-scheme handler for hotstash:// deep links.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Start the trial countdown and purchase listener.
        TrialManager.shared.start()
        PurchaseManager.shared.listenForTransactions()

        // Anonymous active-user ping (no login, no PII).
        DeviceTracker.recordOpen()

        // Show first-launch onboarding or version What's New.
        showOnboardingIfNeeded()
        showWhatsNewIfNeeded()
        showSignInPromptIfNeeded()
        // App Store update discovery is handled passively by the clipboard
        // panel's "Update available" strip (see ClipboardPanelVC + UpdateChecker).
        // Developer-triggered update notices (Supabase app_update_notice) are
        // shown on launch — these are opt-in per row, so no nag unless enabled.
        Task { await UpdateChecker.presentRemoteNoticeIfNeeded() }
    }

    /// Invites the user to sign in to the marketplace on first launch and after
    /// each update (no-op if already prompted for this version).
    private func showSignInPromptIfNeeded() {
        guard SignInPromptWindowController.shouldPrompt() else { return }
        let wc = SignInPromptWindowController()
        signInPromptWindowController = wc
        // Defer so it lands in front of any onboarding/what's-new window.
        DispatchQueue.main.async { wc.show() }
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

    @objc private func handleQuickTransformNotification(_ note: Notification) {
        guard let slot = note.userInfo?["slot"] as? Int else { return }
        Task { @MainActor in
            QuickTransformRunner.run(slotIndex: slot)
        }
    }

    // MARK: - Deep links

    /// Handles `hotstash://transform/<slug>` URLs: opens Settings, switches to
    /// the Marketplace tab, and routes to the transform's detail.
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         withReplyEvent reply: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString),
            url.scheme == "hotstash"
        else { return }

        // hotstash://transform/<slug>  → host "transform", first path component is the slug.
        guard url.host == "transform" else { return }
        let slug = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        guard !slug.isEmpty else { return }

        AppRouter.shared.openTransform(slug: slug)
        SettingsWindowController.shared.show()
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
