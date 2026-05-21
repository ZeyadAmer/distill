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

    // MARK: - Button configuration

    private func configureButton() {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Distill") {
            image.isTemplate = true
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            button.image = configured
        }

        button.action = #selector(handleButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
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
            title: "Open Distill",
            action: #selector(openDistill),
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
            title: "Quit Distill",
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

    @objc private func openDistill() {
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

    /// Redraws the status item button to add or remove the trial-expired warning dot.
    private func updateBadge() {
        let shouldShowBadge = TrialManager.shared.isRestricted && !PurchaseManager.shared.isPurchased
        guard shouldShowBadge != trialExpiredBadgeVisible else { return }
        trialExpiredBadgeVisible = shouldShowBadge

        guard let button = statusItem.button else { return }

        if shouldShowBadge {
            // Composite the base icon with an orange warning dot.
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            guard
                let baseSymbol = NSImage(
                    systemSymbolName: "doc.on.clipboard",
                    accessibilityDescription: "Distill"
                )
            else { return }

            let base = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol
            let size = NSSize(width: 22, height: 18)
            let composite = NSImage(size: size)

            composite.lockFocus()

            // Draw the clipboard icon in the horizontal/vertical center.
            let iconRect = NSRect(
                x: (size.width - base.size.width) / 2,
                y: (size.height - base.size.height) / 2,
                width: base.size.width,
                height: base.size.height
            )
            base.draw(in: iconRect)

            // Draw the orange dot in the top-right corner.
            let dotDiameter: CGFloat = 6
            let dotRect = NSRect(
                x: size.width - dotDiameter - 1,
                y: size.height - dotDiameter - 1,
                width: dotDiameter,
                height: dotDiameter
            )
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            composite.unlockFocus()
            composite.isTemplate = false
            button.image = composite
        } else {
            // Restore the plain template icon.
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Distill"
            ) {
                let configured = image.withSymbolConfiguration(config) ?? image
                configured.isTemplate = true
                button.image = configured
            }
        }
    }
}
