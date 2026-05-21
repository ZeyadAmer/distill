import AppKit
import Carbon
import Foundation

// MARK: - HotkeyManager

/// Manages registration and live re-registration of the global hotkey.
/// Stores the user's chosen key/modifier pair in UserDefaults.
@MainActor
final class HotkeyManager {

    static let shared = HotkeyManager()
    private init() {}

    // MARK: - Keys

    private enum Keys {
        static let keyCode   = "hotkeyKeyCode"
        static let modifiers = "hotkeyModifiers"
    }

    private static let defaultKeyCode:   UInt32 = UInt32(kVK_ANSI_V)
    private static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    // MARK: - Persisted values

    var keyCode: UInt32 {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.keyCode)
            return v > 0 ? UInt32(v) : Self.defaultKeyCode
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.keyCode) }
    }

    var modifiers: UInt32 {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.modifiers)
            return v > 0 ? UInt32(v) : Self.defaultModifiers
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.modifiers) }
    }

    // MARK: - Carbon refs

    private var hotKeyRef: EventHotKeyRef?
    private var multiPasteHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - Multi-paste hotkey (CMD+Shift+L, fixed)

    private static let multiPasteKeyCode:  UInt32 = 37 // kVK_ANSI_L
    private static let multiPasteModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    // MARK: - Lifecycle

    func start() {
        installEventHandler()
        registerHotKey()
        registerMultiPasteHotKey()
    }

    /// Replaces the main hotkey and immediately re-registers it.
    func update(keyCode newCode: UInt32, modifiers newMods: UInt32) {
        unregisterHotKey()
        keyCode   = newCode
        modifiers = newMods
        registerHotKey()
    }

    // MARK: - Display

    var displayString: String {
        Self.displayString(keyCode: keyCode, carbonModifiers: modifiers)
    }

    static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyCodeToChar(keyCode)
        return s
    }

    /// Converts NSEvent modifier flags to the Carbon modifier bitmask used by RegisterEventHotKey.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    // MARK: - Private

    private func installEventHandler() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    if id == 1 {
                        NotificationCenter.default.post(name: .hotstashHotkeyPressed, object: nil)
                    } else if id == 2 {
                        NotificationCenter.default.post(name: .hotstashMultiPastePressed, object: nil)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func registerHotKey() {
        let id = EventHotKeyID(signature: fourCharCode("HOTS"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func registerMultiPasteHotKey() {
        let id = EventHotKeyID(signature: fourCharCode("HOTS"), id: 2)
        RegisterEventHotKey(
            Self.multiPasteKeyCode,
            Self.multiPasteModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &multiPasteHotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

// MARK: - Key code → character

private func keyCodeToChar(_ keyCode: UInt32) -> String {
    let map: [UInt32: String] = [
        0: "A",  11: "B",  8: "C",   2: "D",  14: "E",   3: "F",   5: "G",   4: "H",
       34: "I",  38: "J", 40: "K",  37: "L",  46: "M",  45: "N",  31: "O",  35: "P",
       12: "Q",  15: "R",  1: "S",  17: "T",  32: "U",   9: "V",  13: "W",   7: "X",
       16: "Y",   6: "Z",
       29: "0",  18: "1", 19: "2",  20: "3",  21: "4",  23: "5",  22: "6",  26: "7",
       28: "8",  25: "9",
      122: "F1", 120: "F2",  99: "F3", 118: "F4",  96: "F5",  97: "F6",
       98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
       36: "↩",  48: "⇥",  49: "␣",  51: "⌫",  53: "⎋",
      123: "←", 124: "→", 125: "↓", 126: "↑",
       27: "-",  24: "+",  33: "[",  30: "]",  44: "/",
    ]
    return map[keyCode] ?? "?"
}
