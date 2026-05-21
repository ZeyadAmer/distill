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

    // MARK: Init

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        observePurchaseState()
        updateBadge()
    }

    // MARK: - Public accessors

    /// The status bar button, needed for positioning the panel below the icon.
    var statusItemButton: NSStatusBarButton? { statusItem.button }

    // MARK: - Button configuration

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = makeFlameClipboardImage(warningDot: false)
        button.action = #selector(handleButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    // MARK: - Icon drawing

    /// Builds a clipboard + flame composite image for the status bar.
    /// When `warningDot` is true, adds a small red dot to indicate an expired trial.
    private func makeFlameClipboardImage(warningDot: Bool) -> NSImage {
        let totalSize = NSSize(width: 22, height: 18)
        let composite = NSImage(size: totalSize)

        composite.lockFocus()

        // Clipboard — palette color bakes white directly into the symbol rendering
        let clipConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let clip = NSImage(systemSymbolName: "doc.on.clipboard",
                              accessibilityDescription: "Hotstash")?
            .withSymbolConfiguration(clipConfig) {
            let cw = clip.size.width
            let ch = clip.size.height
            clip.draw(in: NSRect(x: 1, y: (totalSize.height - ch) / 2, width: cw, height: ch))
        }

        // Flame badge (bottom-right, always orange)
        let flameConfig = NSImage.SymbolConfiguration(pointSize: 7.5, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        if let flame = NSImage(systemSymbolName: "flame.fill",
                               accessibilityDescription: nil)?
            .withSymbolConfiguration(flameConfig) {
            let fw = flame.size.width
            let fh = flame.size.height
            flame.draw(in: NSRect(x: totalSize.width - fw - 0.5, y: 0, width: fw, height: fh))
        }

        // Optional red warning dot (top-right corner)
        if warningDot {
            let dotDiameter: CGFloat = 5
            NSColor.systemRed.setFill()
            let dotRect = NSRect(x: totalSize.width - dotDiameter - 0.5,
                                 y: totalSize.height - dotDiameter - 0.5,
                                 width: dotDiameter, height: dotDiameter)
            NSBezierPath(ovalIn: dotRect).fill()
        }

        composite.unlockFocus()
        composite.isTemplate = false
        return composite
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
        let showDot = TrialManager.shared.isRestricted && !PurchaseManager.shared.isPurchased
        guard showDot != trialExpiredBadgeVisible else { return }
        trialExpiredBadgeVisible = showDot
        statusItem.button?.image = makeFlameClipboardImage(warningDot: showDot)
    }
}
