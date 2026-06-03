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

    /// Signed-in token passed to both surfaces. Wired in Commit 5.
    var accessToken: String?

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
