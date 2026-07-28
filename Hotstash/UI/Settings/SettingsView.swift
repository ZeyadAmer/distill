import SwiftUI

// MARK: - SettingsRootView

/// Root container for the settings window — four-tab layout. The selected tab
/// is driven by `AppRouter` so deep links can switch to the marketplace.
struct SettingsRootView: View {
    @ObservedObject private var router = AppRouter.shared

    /// Local mirror of `router.selectedTab`. Binding the TabView straight to
    /// the @Published property makes AppKit's tab bridge publish during the
    /// view update ("Publishing changes from within view updates is not
    /// allowed"); the local state absorbs the write and syncs after.
    @State private var selectedTab: SettingsTab = AppRouter.shared.selectedTab

    var body: some View {
        TabView(selection: $selectedTab) {
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
        .onChange(of: selectedTab) { _, newValue in
            if router.selectedTab != newValue { router.selectedTab = newValue }
        }
        .onReceive(router.$selectedTab) { newValue in
            if selectedTab != newValue { selectedTab = newValue }
        }
    }
}
