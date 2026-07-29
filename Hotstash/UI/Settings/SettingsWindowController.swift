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
        window.title = "Hotstash Settings"
        window.isReleasedWhenClosed = false
        // Follow the user to whatever Space/display they're on instead of
        // staying pinned to the Space it first opened on.
        window.collectionBehavior = [.moveToActiveSpace]

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

    /// Brings the settings window to the front on the user's current Space and
    /// display, centering it on the screen under the cursor.
    func show() {
        showWindow(nil)
        centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centers the window on the screen containing the cursor (falls back to the
    /// main screen), so reopening lands it where the user is looking.
    private func centerOnActiveScreen() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { window.center(); return }
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
