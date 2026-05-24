import SwiftUI

enum AppTab: Hashable {
    case history, transform, snippets, queue, settings
}

struct MainTabView: View {

    @EnvironmentObject private var history:  ClipboardHistoryManager
    @EnvironmentObject private var snippets: SnippetStore
    @EnvironmentObject private var paste:    MultiPasteStore
    @ObservedObject private var purchase = PurchaseManager.shared

    @State private var selectedTab: AppTab = .history

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

                SnippetsView()
                    .tabItem { Label("Snippets", systemImage: "bookmark") }
                    .tag(AppTab.snippets)

                MultiPasteView()
                    .tabItem { Label("Queue", systemImage: "list.number") }
                    .tag(AppTab.queue)

                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(AppTab.settings)
            }
            .onOpenURL { url in
                switch url.host {
                case "history":   selectedTab = .history
                case "transform": selectedTab = .transform
                case "snippets":  selectedTab = .snippets
                case "queue":     selectedTab = .queue
                default:          break
                }
            }
        }
    }
}
