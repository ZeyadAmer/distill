import SwiftUI

// MARK: - MarketplaceSettingsView

/// Settings-window container hosting the storefront and the user's own
/// transforms behind a segmented control.
struct MarketplaceSettingsView: View {

    private enum Tab: String, CaseIterable {
        case browse = "Browse"
        case mine = "My Transforms"
        case review = "Review"
    }

    @State private var tab: Tab = .browse
    @State private var nameDraft: String = ""

    /// Signed-in session for the marketplace. Auth-gated controls (publish,
    /// rate, review, report) are hidden until `accessToken` is non-nil.
    @ObservedObject private var auth = AuthManager.shared

    private var accessToken: String? { auth.accessToken }

    /// Review tab is admin-only.
    private var availableTabs: [Tab] {
        auth.isAdmin ? Tab.allCases : [.browse, .mine]
    }

    var body: some View {
        VStack(spacing: 0) {
            authBar

            Divider()

            Picker("", selection: $tab) {
                ForEach(availableTabs, id: \.self) { Text($0.rawValue).tag($0) }
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
            case .review:
                if let token = accessToken, auth.isAdmin {
                    ReviewQueueView(accessToken: token)
                } else {
                    Text("Admins only.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // If admin status changes (e.g. sign-out) while on Review, fall back.
        .onChange(of: auth.isAdmin) { _ in
            if !availableTabs.contains(tab) { tab = .browse }
        }
        .onAppear { nameDraft = auth.displayName ?? "" }
        .onChange(of: auth.displayName) { newValue in nameDraft = newValue ?? "" }
        // Re-validate a Keychain-restored session and refresh admin status.
        .task { await auth.restoreSession() }
    }

    @ViewBuilder
    private var authBar: some View {
        HStack(spacing: 10) {
            Image(systemName: auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .foregroundStyle(auth.isSignedIn ? .green : .secondary)
            if auth.isSignedIn {
                TextField("Display name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("Save") { Task { await auth.updateDisplayName(nameDraft) } }
                    .controlSize(.small)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
                              || nameDraft == auth.displayName)
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
