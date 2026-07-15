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
            icon: "sparkles",
            title: "Generate transforms with AI",
            detail: "Describe what you want and give one example — Hotstash writes the transform for you, checks it against your example, and keeps fixing it until it matches. No JavaScript required. (Pro)"
        ),
        ChangeItem(
            icon: "chart.bar.fill",
            title: "System stats in the menu bar",
            detail: "Keep an eye on your Mac right from the menu bar. Show live CPU, memory, and free disk space next to the Hotstash icon — pick exactly what you want in Settings."
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
