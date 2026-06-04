import AppKit
import SwiftUI

// MARK: - WhatsNewWindowController

final class WhatsNewWindowController: NSWindowController {

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 500, height: 500)
        let styleMask: NSWindow.StyleMask = [.titled, .closable]

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "What's New in Hotstash"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: WhatsNewView())
        window.contentView = hostingView

        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - WhatsNewView

struct WhatsNewView: View {

    private struct ChangeItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let items: [ChangeItem] = [
        ChangeItem(
            icon: "return",
            title: "Press Return to paste",
            detail: "Pick an item with the ↑/↓ arrows and hit Return — or double-click — to paste it straight into the app you were just using. No more switching back and pressing ⌘V."
        ),
        ChangeItem(
            icon: "arrow.up.arrow.down",
            title: "Arrow-key navigation",
            detail: "After the hotkey, the arrows move through your history while you keep typing to search."
        ),
        ChangeItem(
            icon: "wand.and.stars",
            title: "Quick Transform shortcuts",
            detail: "Map up to five global shortcuts to a transform — e.g. ⌘G to paste in UPPERCASE. Copy, press the key, done."
        ),
        ChangeItem(
            icon: "arrow.down.circle",
            title: "Update reminders",
            detail: "Hotstash now tells you when a new version is available on the App Store."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)

                Text("What's New")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Version 5.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            // Feature list
            VStack(alignment: .leading, spacing: 16) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 36)

            Spacer()

            // CTA
            Button {
                NSApp.keyWindow?.close()
            } label: {
                Text("Continue")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 28)
        }
        .frame(width: 500, height: 500)
    }
}
