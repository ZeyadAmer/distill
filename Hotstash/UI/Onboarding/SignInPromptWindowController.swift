import AppKit
import SwiftUI

// MARK: - SignInPromptWindowController

/// A small prompt inviting the user to sign in to the marketplace. Shown once
/// on first launch and once after each app update (sign-in itself is optional —
/// browsing/using transforms works without it; signing in enables publishing,
/// rating, and reviewing).
@MainActor
final class SignInPromptWindowController: NSWindowController {

    private enum Keys {
        static let hasPrompted = "com.zeyadamer.hotstash.hasPromptedSignIn"
        static let lastPromptVersion = "com.zeyadamer.hotstash.signInPromptVersion"
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Hotstash Marketplace"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: SignInPromptView { window.close() })
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Decides whether to show: first launch ever, or the app version changed
    /// since the last prompt. Records that it prompted so it won't nag.
    static func shouldPrompt(defaults: UserDefaults = .standard) -> Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if !defaults.bool(forKey: Keys.hasPrompted) { return true }
        return defaults.string(forKey: Keys.lastPromptVersion) != current
    }

    static func markPrompted(defaults: UserDefaults = .standard) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        defaults.set(true, forKey: Keys.hasPrompted)
        defaults.set(current, forKey: Keys.lastPromptVersion)
    }

    func show() {
        Self.markPrompted()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SignInPromptView

private struct SignInPromptView: View {
    let onClose: () -> Void
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bag.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 28)

            Text("Sign in to the Marketplace")
                .font(.title2).bold()

            Text("Sign in with Apple to publish your own transforms, rate, and review. Browsing and using transforms works without an account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            if auth.isSignedIn {
                Label("Signed in as \(auth.displayName ?? "you")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    if auth.isSignedIn { onClose() } else { auth.signIn() }
                } label: {
                    Text(auth.isSignedIn ? "Done" : "Sign in with Apple").frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!auth.canSignIn && !auth.isSignedIn)

                Button("Maybe later", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                if !auth.canSignIn {
                    Text("Marketplace backend not configured.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 360)
        .onChange(of: auth.isSignedIn) { signedIn in
            if signedIn { onClose() }
        }
    }
}
