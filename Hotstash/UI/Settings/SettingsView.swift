import SwiftUI

// MARK: - SettingsRootView

/// Root container for the settings window — three-tab layout.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TransformSettingsView()
                .tabItem {
                    Label("Transforms", systemImage: "wand.and.stars")
                }

            MarketplaceSettingsView()
                .tabItem {
                    Label("Marketplace", systemImage: "bag")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 560)
    }
}
