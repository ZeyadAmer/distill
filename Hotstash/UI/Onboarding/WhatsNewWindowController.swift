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
            icon: "face.smiling",
            title: "Emoji transform icons",
            detail: "Give any transform an emoji instead of a symbol. Edit a transform, switch the icon to Emoji, and pick one — ⌃⌘Space opens the macOS emoji picker."
        ),
        ChangeItem(
            icon: "photo",
            title: "Custom image icons",
            detail: "Use your own artwork. Choose any image while editing a transform; it's resized to a crisp 64×64 icon and travels with the transform when you publish it."
        ),
        ChangeItem(
            icon: "sparkles",
            title: "Marketplace shows real icons",
            detail: "Browse and My Transforms now display each transform's actual icon — emoji, image, or symbol — instead of a generic glyph."
        ),
        ChangeItem(
            icon: "arrow.triangle.2.circlepath",
            title: "Icons sync everywhere",
            detail: "Whatever icon you set follows the transform across your Mac, iPhone, and to everyone who installs it — no rebuild needed."
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

                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
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
