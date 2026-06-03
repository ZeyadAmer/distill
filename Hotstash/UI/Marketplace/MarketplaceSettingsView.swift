import SwiftUI

// MARK: - MarketplaceSettingsView

/// Settings-window container hosting the storefront and the user's own
/// transforms behind a segmented control.
struct MarketplaceSettingsView: View {

    private enum Tab: String, CaseIterable {
        case browse = "Browse"
        case mine = "My Transforms"
    }

    @State private var tab: Tab = .browse

    /// Signed-in session for the marketplace. Auth-gated controls (publish,
    /// rate, review, report) are hidden until `accessToken` is non-nil.
    @ObservedObject private var auth = AuthManager.shared

    private var accessToken: String? { auth.accessToken }

    var body: some View {
        VStack(spacing: 0) {
            authBar

            Divider()

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch tab {
            case .browse:
                MarketplaceView(accessToken: accessToken)
            case .mine:
                MyTransformsView(accessToken: accessToken)
            }
        }
    }

    @ViewBuilder
    private var authBar: some View {
        HStack(spacing: 10) {
            Image(systemName: auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .foregroundStyle(auth.isSignedIn ? .green : .secondary)
            if auth.isSignedIn {
                Text(auth.displayName ?? "Signed in")
                    .font(.callout)
                Spacer()
                Button("Sign Out") { auth.signOut() }
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not signed in").font(.callout)
                    Text(auth.canSignIn
                         ? "Sign in to publish, rate, and review."
                         : "Configure Supabase.plist to enable publishing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign in with Apple") { auth.signIn() }
                    .controlSize(.small)
                    .disabled(!auth.canSignIn || auth.isSigningIn)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if let error = auth.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
        }
    }
}
