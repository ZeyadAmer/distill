import SwiftUI

@main
struct HotstashApp: App {

    @Environment(\.scenePhase) private var scenePhase

    private let history  = ClipboardHistoryManager.shared
    private let snippets = SnippetStore.shared
    private let paste    = MultiPasteStore.shared

    init() {
        TrialManager.shared.start()
        PurchaseManager.shared.listenForTransactions()
        // Installed marketplace transforms join the built-ins in every picker.
        // Image-kind transforms are macOS-only, so only text ones surface here.
        IOSTransforms.extraProvider = {
            MarketplaceLibrary.shared.customTransforms().filter {
                ($0 as? MarketplaceTransform)?.manifest.kind != .image
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(history)
                .environmentObject(snippets)
                .environmentObject(paste)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { @MainActor in
                    history.checkClipboard()
                }
            }
        }
    }
}
