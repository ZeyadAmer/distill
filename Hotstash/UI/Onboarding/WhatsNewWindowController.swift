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
            icon: "folder.fill",
            title: "Folders",
            detail: "Give your clips a home. Keep one folder for API keys, another for the snippets you paste all day, and tuck things away with a right-click. They live right next to Recents and Pinned, and they never get swept up when history clears."
        ),
        ChangeItem(
            icon: "tag.fill",
            title: "Name anything",
            detail: "Right-click a clip and call it whatever sticks — \u{201C}supabase\u{201D}, \u{201C}work email\u{201D}, you name it. Then just search that name to pull it back in a second."
        ),
        ChangeItem(
            icon: "magnifyingglass",
            title: "Smarter search",
            detail: "Search now puts the clips you've named right at the top, so typing a name you gave something takes you straight to it."
        ),
        ChangeItem(
            icon: "link",
            title: "Clean up links",
            detail: "Copied a link from Instagram, Facebook, or anywhere else? Strip out the tracking junk with one click — it'll even follow share redirects to grab the real destination first."
        ),
        ChangeItem(
            icon: "wand.and.stars",
            title: "Stack your transforms",
            detail: "Hold ⌘ and pick as many transforms as you like. Trim it, lowercase it, wrap it in quotes — all at once, in the order you choose."
        ),
        ChangeItem(
            icon: "face.smiling",
            title: "Custom transform icons",
            detail: "Give any transform an emoji or your own image — not just a symbol. Pick one while editing: ⌃⌘Space opens the emoji picker, or choose an image and it's saved as a crisp 64×64 icon."
        ),
        ChangeItem(
            icon: "sparkles",
            title: "Marketplace shows real icons",
            detail: "Browse and My Transforms now show each transform's actual icon — emoji, image, or symbol — and it syncs to everyone who installs it."
        ),
        ChangeItem(
            icon: "arrow.up.left.and.arrow.down.right",
            title: "A panel that stays put",
            detail: "Drag the window to the size and spot that suit you. It opens right back there next time instead of snapping under the menu bar."
        ),
        ChangeItem(
            icon: "eye",
            title: "Peek before you paste",
            detail: "Hover over any clip to see the whole thing in a tooltip — no need to open it just to remember what's inside."
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
            .padding(.bottom, 20)

            // Feature list
            ScrollView {
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
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 12)
            }

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
