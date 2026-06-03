import SwiftUI

// MARK: - SettingsRootView

/// Root container for the settings window — four-tab layout. The selected tab
/// is driven by `AppRouter` so deep links can switch to the marketplace.
struct SettingsRootView: View {
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            TransformSettingsView()
                .tabItem { Label("Transforms", systemImage: "wand.and.stars") }
                .tag(SettingsTab.transforms)

            MarketplaceSettingsView()
                .tabItem { Label("Marketplace", systemImage: "bag") }
                .tag(SettingsTab.marketplace)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 560)
    }
}
