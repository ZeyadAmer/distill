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

    /// Signed-in token passed to both surfaces. Hidden while nil.
    /// TODO(S4): `AuthManager` is a stub until real Sign in with Apple lands.
    @ObservedObject private var auth = AuthManager.shared

    private var accessToken: String? { auth.accessToken }

    var body: some View {
        VStack(spacing: 0) {
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
}
