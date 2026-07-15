import AppKit

// MARK: - MenuBarManager

/// Owns the NSStatusItem and routes clicks to the clipboard panel or context menu.
@MainActor
final class MenuBarManager: NSObject {

    // MARK: Singleton

    static let shared = MenuBarManager()

    // MARK: Private state

    private let statusItem: NSStatusItem
    private var trialExpiredBadgeVisible = false
    private var statsTimer: Timer?

    // MARK: Init

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        observePurchaseState()
        updateBadge()
        observeStatsPreference()
        startStatsTimerIfNeeded()
    }

    // MARK: - Public accessors

    /// The status bar button, needed for positioning the panel below the icon.
    var statusItemButton: NSStatusBarButton? { statusItem.button }

    // MARK: - Button configuration

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = makeStatusIcon()
        button.imagePosition = .imageTrailing
        button.action = #selector(handleButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    // MARK: - Icon drawing

    /// Template flame icon — the system tints it for light/dark menu bars,
    /// hover highlight, and reduced-transparency modes automatically.
    private func makeStatusIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let icon = NSImage(systemSymbolName: "flame.fill",
                           accessibilityDescription: "Hotstash")?
            .withSymbolConfiguration(config) ?? NSImage()
        icon.isTemplate = true
        return icon
    }

    // MARK: - Click handling

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp:
            ClipboardPanel.shared.toggle()
        default:
            ClipboardPanel.shared.toggle()
        }
    }

    // MARK: - Context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Hotstash",
            action: #selector(openHotstash),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Hotstash",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu reference after display so left-click still routes
        // through our action handler rather than popping the menu again.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - Menu actions

    @objc private func openHotstash() {
        ClipboardPanel.shared.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Purchase state observation

    private func observePurchaseState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePurchaseStateChanged),
            name: .purchaseStateChanged,
            object: nil
        )
    }

    @objc private func handlePurchaseStateChanged() {
        updateBadge()
    }

    // MARK: - Badge drawing

    private func updateBadge() {
        let showWarning = TrialManager.shared.isRestricted && !PurchaseManager.shared.isPurchased
        guard showWarning != trialExpiredBadgeVisible else { return }
        trialExpiredBadgeVisible = showWarning
        // Orange tint overrides the template's automatic menu-bar color
        // while the trial is expired; nil restores system behavior.
        statusItem.button?.contentTintColor = showWarning ? .systemOrange : nil
        statusItem.button?.toolTip = showWarning ? "Hotstash — trial expired" : "Hotstash"
    }

    // MARK: - Menu bar stats

    private func observeStatsPreference() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStatsPreferenceChanged),
            name: .menuBarStatsPreferenceChanged,
            object: nil
        )
    }

    @objc private func handleStatsPreferenceChanged() {
        startStatsTimerIfNeeded()
    }

    private func startStatsTimerIfNeeded() {
        statsTimer?.invalidate()
        statsTimer = nil

        guard !MenuBarStatsPreference.selected.isEmpty else {
            statusItem.button?.title = ""
            return
        }

        updateStatsTitle()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatsTitle() }
        }
    }

    private func updateStatsTitle() {
        let kinds = MenuBarStatsPreference.selected
        guard !kinds.isEmpty else {
            statusItem.button?.title = ""
            return
        }
        let text = kinds
            .map { SystemStatsMonitor.shared.formattedValue(for: $0) }
            .joined(separator: "  ")
        // Trailing space — imageTrailing butts the icon straight against the
        // title otherwise, with no layout knob to add a gap.
        statusItem.button?.title = text + " "
    }
}
