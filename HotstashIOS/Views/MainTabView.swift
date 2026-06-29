import SwiftUI

enum AppTab: Hashable {
    case history, transform, marketplace, snippets, queue, settings
}

struct MainTabView: View {

    @EnvironmentObject private var history:  ClipboardHistoryManager
    @EnvironmentObject private var snippets: SnippetStore
    @EnvironmentObject private var paste:    MultiPasteStore
    @ObservedObject private var purchase = PurchaseManager.shared

    @State private var selectedTab: AppTab = .history

    /// First-run keyboard-setup prompt — shown once so users discover the
    /// custom keyboard, which otherwise stays invisible until enabled.
    @AppStorage("hasSeenKeyboardSetup") private var hasSeenKeyboardSetup = false
    @State private var showKeyboardSetup = false

    private var isRestricted: Bool {
        !TrialManager.shared.isInTrial && !purchase.isPurchased
    }

    var body: some View {
        if isRestricted {
            PaywallView()
        } else {
            TabView(selection: $selectedTab) {
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                    .tag(AppTab.history)

                TransformView()
                    .tabItem { Label("Transform", systemImage: "wand.and.sparkles") }
                    .tag(AppTab.transform)

                NavigationStack { MarketplaceView() }
                    .tabItem { Label("Market", systemImage: "storefront") }
                    .tag(AppTab.marketplace)

                SnippetsView()
                    .tabItem { Label("Snippets", systemImage: "bookmark") }
                    .tag(AppTab.snippets)

                MultiPasteView()
                    .tabItem { Label("Queue", systemImage: "list.number") }
                    .tag(AppTab.queue)

                AboutView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .onOpenURL { url in
                switch url.host {
                case "history":     selectedTab = .history
                case "transform":   selectedTab = .transform
                case "marketplace": selectedTab = .marketplace
                case "snippets":    selectedTab = .snippets
                case "queue":       selectedTab = .queue
                default:            break
                }
            }
            .sheet(isPresented: $showKeyboardSetup) { KeyboardSetupView() }
            .onAppear {
                if !hasSeenKeyboardSetup {
                    hasSeenKeyboardSetup = true
                    showKeyboardSetup = true
                }
            }
        }
    }
}
