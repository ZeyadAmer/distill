import Foundation

extension Notification.Name {
    /// Posted when the global CMD+Shift+V hotkey is pressed.
    static let hotstashHotkeyPressed = Notification.Name("com.zeyadamer.hotstash.hotkeyPressed")

    /// Posted whenever the clipboard store receives a new item from NSPasteboard.
    static let clipboardDidUpdate = Notification.Name("com.zeyadamer.hotstash.clipboardDidUpdate")

    /// Posted when the purchase or trial state changes (unlocked, trial expired, etc.).
    static let purchaseStateChanged = Notification.Name("com.zeyadamer.hotstash.purchaseStateChanged")
}
