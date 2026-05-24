import AppIntents

struct HotstashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveClipboardIntent(),
            phrases: [
                "Save to \(.applicationName)",
                "Save clipboard to \(.applicationName)",
                "Add clipboard to \(.applicationName)"
            ],
            shortTitle: "Save Clipboard",
            systemImageName: "plus.square.on.square"
        )
    }
}
