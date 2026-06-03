import AppKit

// MARK: - AppMenu

/// Installs a minimal main menu. As a menu-bar (accessory) app Hotstash has no
/// visible menu bar, but `NSApp.mainMenu` is still what wires the standard
/// editing key equivalents (⌘X/⌘C/⌘V/⌘A, ⌘Z/⇧⌘Z) into the responder chain —
/// without it, text fields in Settings/marketplace can't cut, copy, or paste.
enum AppMenu {

    @MainActor
    static func install() {
        let mainMenu = NSMenu()

        // App menu (provides ⌘Q).
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit Hotstash",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // Edit menu (the part that actually enables copy/paste in text fields).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }
}
