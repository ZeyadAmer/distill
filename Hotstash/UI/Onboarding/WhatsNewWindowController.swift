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
            icon: "pin.circle.fill",
            title: "Pinned & Recents tabs",
            detail: "Browse your pinned and recent clips in separate tabs — no more scrolling past a long pinned list."
        ),
        ChangeItem(
            icon: "keyboard",
            title: "⌘1–⌘9 instant paste",
            detail: "Press ⌘1–⌘9 to paste any item by position the moment the panel opens — no click required."
        ),
        ChangeItem(
            icon: "cursorarrow.click",
            title: "Click to copy, double-click to close",
            detail: "Single click copies an item to your clipboard. Double-click copies and dismisses the panel."
        ),
        ChangeItem(
            icon: "photo.badge.arrow.down.fill",
            title: "More image transforms",
            detail: "Convert images to WebP, PNG, Grayscale, resize to 50%, flip horizontally, or rotate 90°."
        ),
        ChangeItem(
            icon: "text.badge.checkmark",
            title: "Smarter Trim Whitespace",
            detail: "Trim Whitespace now also collapses extra spaces between words, not just leading and trailing edges."
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

                Text("Version 3.0")
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
