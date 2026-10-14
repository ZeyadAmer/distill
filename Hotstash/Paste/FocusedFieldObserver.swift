import AppKit
import ApplicationServices

// MARK: - FocusedFieldObserver

/// Reports the accessibility text (label, placeholder, identifier…) of the
/// focused UI element in the frontmost app whenever focus moves. Paste Stack
/// uses it to stage the item that fits the field. Needs Accessibility access,
/// which Paste Stack already requires.
@MainActor
final class FocusedFieldObserver {

    var onChange: ((String) -> Void)?

    private var observer: AXObserver?
    private var activationToken: NSObjectProtocol?
    /// App whose AXEnhancedUserInterface we switched on; switched back off on detach.
    private var enhancedApp: AXUIElement?

    /// Chromium browsers only build their web accessibility tree (form fields)
    /// when AXEnhancedUserInterface is on. Electron apps use AXManualAccessibility.
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    func start() {
        guard activationToken == nil else { return }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.attach(to: app) }
        }
        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        if let token = activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            activationToken = nil
        }
        detach()
    }

    // MARK: Private

    private func attach(to app: NSRunningApplication?) {
        detach()
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        // Chromium and Electron apps only expose web form fields when asked.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if Self.chromiumBrowsers.contains(app.bundleIdentifier ?? "") {
            var current: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &current)
            if (current as? Bool) != true,
               AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success {
                enhancedApp = appElement
            }
        }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<FocusedFieldObserver>.fromOpaque(refcon).takeUnretainedValue()
            let text = FocusedFieldObserver.describe(element)
            MainActor.assumeIsolated { me.onChange?(text) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created

        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            onChange?(Self.describe(focused as! AXUIElement))
        }
    }

    private func detach() {
        if let enhancedApp {
            AXUIElementSetAttributeValue(enhancedApp, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            self.enhancedApp = nil
        }
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    /// Everything that names the field, joined: its own title, description,
    /// placeholder, help and identifiers, plus the text of its label element.
    nonisolated private static func describe(_ element: AXUIElement) -> String {
        let attributes = [
            kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute,
            kAXHelpAttribute, kAXIdentifierAttribute, "AXDOMIdentifier",
        ]
        var parts = attributes.compactMap { string(element, $0 as String) }

        var labelRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &labelRef) == .success,
           let labelRef, CFGetTypeID(labelRef) == AXUIElementGetTypeID() {
            let label = labelRef as! AXUIElement
            parts += [string(label, kAXValueAttribute), string(label, kAXTitleAttribute)].compactMap { $0 }
        }
        return parts.joined(separator: " ")
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
