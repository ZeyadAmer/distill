import AppKit

// MARK: - ClipboardPanel

/// The floating, frameless panel that hosts the clipboard history UI.
///
/// The panel uses a `NSVisualEffectView` background with `.popover` material so
/// it picks up the correct system blurring on both light and dark mode.  It
/// floats above every other application window and dismisses when the user
/// clicks outside it or presses Escape.
@MainActor
final class ClipboardPanel: NSPanel {

    // MARK: Singleton

    static let shared = ClipboardPanel()

    // MARK: Geometry

    private static let panelWidth:  CGFloat = 480
    private static let panelHeight: CGFloat = 520
    private static let cornerRadius: CGFloat = 12

    // MARK: Internal state

    private var outsideClickMonitor: Any?
    private var localKeyMonitor: Any?
    private let contentVC = ClipboardPanelVC()

    // MARK: Init

    private init() {
        let initialRect = NSRect(
            x: 0, y: 0,
            width:  Self.panelWidth,
            height: Self.panelHeight
        )
        super.init(
            contentRect: initialRect,
            styleMask:   [.borderless, .nonactivatingPanel, .hudWindow],
            backing:     .buffered,
            defer:       false
        )
        configure()
    }

    // MARK: - Configuration

    private func configure() {
        level               = .floating
        collectionBehavior  = [.canJoinAllSpaces, .transient, .ignoresCycle]
        isOpaque            = false
        backgroundColor     = .clear
        hasShadow           = true
        isMovableByWindowBackground = true

        // Set VC first so contentView is contentVC.view.
        contentViewController = contentVC

        // Add a visual effect view as the BOTTOM-most subview for the blur background.
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.cornerRadius = Self.cornerRadius
        cv.layer?.masksToBounds = true

        let effectView = NSVisualEffectView(frame: cv.bounds)
        effectView.material       = .popover
        effectView.blendingMode   = .withinWindow
        effectView.state          = .active
        effectView.autoresizingMask = [.width, .height]
        cv.addSubview(effectView, positioned: .below, relativeTo: nil)

        installEventMonitors()
    }

    // MARK: - Event Monitors

    private func installEventMonitors() {
        // Global left-click outside the panel → dismiss.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.hide()
        }

        // Local Escape key → dismiss.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // kVK_Escape = 53
                self?.hide()
                return nil // consume the event
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Show / Hide

    /// Toggles the panel: hides it when visible, shows it near the cursor otherwise.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Positions the panel near the mouse cursor, then fades it in.
    func show() {
        positionNearCursor()
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        contentVC.panelWillShow()
    }

    /// Fades out the panel, then moves it off screen.
    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    // MARK: - Positioning

    /// Computes a frame for the panel that sits close to — but not under — the
    /// current mouse cursor, clamping to the visible area of the active screen.
    private func positionNearCursor() {
        let cursor  = NSEvent.mouseLocation
        let screen  = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                      ?? NSScreen.main
                      ?? NSScreen.screens[0]

        let visible = screen.visibleFrame
        let w = Self.panelWidth
        let h = Self.panelHeight

        // Offset so the panel appears slightly below-right of the cursor.
        let offsetX: CGFloat =  12
        let offsetY: CGFloat = -12

        var x = cursor.x + offsetX
        var y = cursor.y + offsetY - h   // Flip: AppKit y grows upward

        // Clamp horizontally.
        if x + w > visible.maxX { x = visible.maxX - w - 8 }
        if x < visible.minX     { x = visible.minX + 8 }

        // Clamp vertically.
        if y < visible.minY             { y = visible.minY + 8 }
        if y + h > visible.maxY         { y = visible.maxY - h - 8 }

        setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
    }

    // MARK: - NSPanel overrides

    /// Allow the panel to become key so keyboard navigation works.
    override var canBecomeKey: Bool { true }
}
