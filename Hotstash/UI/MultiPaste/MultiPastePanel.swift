import AppKit
import SwiftUI

// MARK: - MultiPastePanel

/// Small floating panel that asks "how many?" and "how to join?" then pastes.
@MainActor
final class MultiPastePanel: NSPanel {

    static let shared = MultiPastePanel()

    private let contentVC: NSViewController

    private init() {
        let vc = NSHostingController(rootView: MultiPasteView(onDismiss: {
            MultiPastePanel.shared.hide()
        }))
        contentVC = vc

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 150),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        level               = .floating
        isOpaque            = false
        backgroundColor     = .clear
        hasShadow           = true
        collectionBehavior  = [.canJoinAllSpaces, .transient]

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 280, height: 150))
        effect.material       = .popover
        effect.blendingMode   = .behindWindow
        effect.state          = .active
        effect.wantsLayer     = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let hostingView = vc.view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        contentView = effect

        installEscapeMonitor()
    }

    private var escapeMonitor: Any?

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }

    // MARK: - Show / Hide

    func show() {
        positionNearCursor()
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    private func positionNearCursor() {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                     ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let w = frame.width
        let h = frame.height
        var x = cursor.x + 12
        var y = cursor.y - h - 12
        if x + w > visible.maxX { x = visible.maxX - w - 8 }
        if x < visible.minX     { x = visible.minX + 8 }
        if y < visible.minY     { y = cursor.y + 12 }
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - MultiPasteView

private struct MultiPasteView: View {

    let onDismiss: () -> Void

    @State private var count: Int = 3
    @State private var joinStyle: JoinStyle = .newLine

    enum JoinStyle: String, CaseIterable {
        case inline  = "Inline"
        case newLine = "New Lines"

        var separator: String {
            self == .inline ? " " : "\n"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Paste Last Items")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Count:")
                    .foregroundStyle(.secondary)

                TextField("", value: $count, format: .number)
                    .frame(width: 48)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { count = min(max(count, 1), 20) }

                Stepper("", value: $count, in: 1...20)
                    .labelsHidden()
            }

            Picker("", selection: $joinStyle) {
                ForEach(JoinStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Copy") { paste() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func paste() {
        onDismiss()

        Task { @MainActor in
            let items = ClipboardStore.shared.recentItems
                .prefix(count)
                .map { $0.content }
            guard !items.isEmpty else { return }
            let joined = items.joined(separator: joinStyle.separator)
            PasteEngine.hotstashedPaste(joined)
        }
    }
}
