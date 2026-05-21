import AppKit
import SwiftUI

// MARK: - SettingsWindowController

/// Singleton window controller that hosts the SwiftUI settings interface.
@MainActor
final class SettingsWindowController: NSWindowController {

    // MARK: Singleton

    static let shared = SettingsWindowController()

    // MARK: Init

    private init() {
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 360)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Distill Settings"
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: SettingsRootView())
        window.contentView = hostingView

        super.init(window: window)

        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — use SettingsWindowController.shared")
    }

    // MARK: - Public API

    /// Makes the settings window key, orders it front, and activates the app.
    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
