import AppKit
import SwiftUI

// MARK: - HistoryLimitOption

private enum HistoryLimitOption: Hashable {
    case unlimited, twoHundred, fiveHundred, custom
}

// MARK: - GeneralSettingsView

struct GeneralSettingsView: View {

    // MARK: - State

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @State private var hotkeyCode:      UInt32 = HotkeyManager.shared.keyCode
    @State private var hotkeyModifiers: UInt32 = HotkeyManager.shared.modifiers
    @State private var multiPasteCode:      UInt32 = HotkeyManager.shared.multiPasteKeyCode
    @State private var multiPasteModifiers: UInt32 = HotkeyManager.shared.multiPasteModifiers
    @State private var panelPosition: PanelPosition = PanelPosition.current
    @State private var showingClearConfirmation = false
    @State private var accessibilityTrusted: Bool = AutoPasteService.isTrusted
    @State private var assistivePasteEnabled: Bool = AutoPasteService.isEnabled
    @State private var alwaysPlainText: Bool = UserDefaults.standard.bool(forKey: "alwaysPastePlainText")
    @AppStorage("pasteStackMatchesFields") private var pasteStackMatchesFields = true
    @AppStorage(OneTimeClips.defaultsKey) private var expireOneTimeClips = true

    @State private var historyLimitOption: HistoryLimitOption = {
        switch UserDefaults.standard.integer(forKey: "historyLimit") {
        case 0:   return .unlimited
        case 200: return .twoHundred
        case 500: return .fiveHundred
        default:  return .custom
        }
    }()

    @State private var customLimitText: String = {
        let v = UserDefaults.standard.integer(forKey: "historyLimit")
        return v > 0 && v != 200 && v != 500 ? "\(v)" : ""
    }()

    // MARK: - Body

    var body: some View {
        Form {
            // MARK: Startup

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
            } header: {
                Text("Startup")
            }

            // MARK: Menu bar stats

            MenuBarStatsSettingsSection()

            // MARK: Keyboard shortcut

            Section {
                LabeledContent("Open Hotstash") {
                    HotkeyRecorderView(keyCode: $hotkeyCode, modifiers: $hotkeyModifiers)
                }
                LabeledContent("Multi-paste") {
                    HotkeyRecorderView(
                        keyCode: $multiPasteCode,
                        modifiers: $multiPasteModifiers,
                        commit: { code, mods in
                            HotkeyManager.shared.updateMultiPaste(keyCode: code, modifiers: mods)
                        }
                    )
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Click a shortcut field, then press your desired key combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Quick transforms

            QuickTransformsSettingsView()

            // MARK: Accessibility — Assistive Paste

            Section {
                Toggle("Assistive Paste", isOn: $assistivePasteEnabled)
                    .onChange(of: assistivePasteEnabled) { enabled in
                        AutoPasteService.isEnabled = enabled
                        if enabled { accessibilityTrusted = AutoPasteService.requestPermission() }
                    }

                if assistivePasteEnabled && !accessibilityTrusted {
                    LabeledContent("Accessibility access") {
                        Button("Open System Settings\u{2026}") {
                            AutoPasteService.openAccessibilitySettings()
                        }
                    }
                } else if assistivePasteEnabled {
                    LabeledContent("Accessibility access") {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    }
                }
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Assistive Paste is for people who have difficulty pressing keyboard shortcuts. When on, choosing an item inserts it into the app you were using, so you don't have to press ⌘V yourself. It's off by default and needs Accessibility access in System Settings → Privacy & Security. With it off, items are copied to the clipboard and you paste with ⌘V as usual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Pasting

            Section {
                Toggle("Always paste as plain text", isOn: $alwaysPlainText)
                    .onChange(of: alwaysPlainText) { newValue in
                        PasteEngine.alwaysPastePlainText = newValue
                    }
            } header: {
                Text("Pasting")
            } footer: {
                Text("Off: items paste with their original formatting; hold ⇧ and press Return to paste one item as plain text. On: formatting is always stripped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Paste Stack

            Section {
                Toggle("Match form fields", isOn: $pasteStackMatchesFields)
            } header: {
                Text("Paste Stack")
            } footer: {
                Text("When you click into a form field, Paste Stack stages the item that fits it first: an item whose name appears in the field's label, or an email, phone number, or link for fields that ask for one. Other items keep their order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: One-time clips

            Section {
                Toggle("Forget one-time codes and links", isOn: $expireOneTimeClips)
            } header: {
                Text("One-time clips")
            } footer: {
                Text("Verification codes and single-use sign-in or download links are removed from history 10 minutes after you copy them. Pinned, named, and foldered items are always kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Excluded apps

            ExcludedAppsSettingsSection()

            // MARK: Panel position

            Section {
                Picker("Show panel", selection: $panelPosition) {
                    Text("Near cursor").tag(PanelPosition.cursor)
                    Text("Below menu bar icon").tag(PanelPosition.menuBar)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: panelPosition) { newValue in
                    PanelPosition.save(newValue)
                }
            } header: {
                Text("Panel Position")
            }

            // MARK: History

            Section {
                Picker("Limit", selection: $historyLimitOption) {
                    Text("Unlimited").tag(HistoryLimitOption.unlimited)
                    Text("200 items").tag(HistoryLimitOption.twoHundred)
                    Text("500 items").tag(HistoryLimitOption.fiveHundred)
                    Text("Custom…").tag(HistoryLimitOption.custom)
                }
                .onChange(of: historyLimitOption) { applyLimit() }

                if historyLimitOption == .custom {
                    HStack(spacing: 8) {
                        TextField("e.g. 1000", text: $customLimitText)
                            .frame(width: 90)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { applyLimit() }
                        Text("items")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Clear History\u{2026}") {
                    showingClearConfirmation = true
                }
                .foregroundStyle(.red)
                .confirmationDialog(
                    "Clear Clipboard History?",
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear History", role: .destructive) {
                        Task { @MainActor in
                            ClipboardStore.shared.clearAll()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all non-pinned items. Pinned items will not be affected.")
                }
            } header: {
                Text("History")
            }

            // MARK: Import

            Section {
                Button("Import from Maccy\u{2026}") { importFromMaccy() }
                Button("Import from Raycast\u{2026}") { importFromRaycast() }
            } header: {
                Text("Import")
            } footer: {
                Text("Maccy: quit Maccy, then choose its folder. Raycast: run \u{201C}Export Settings & Data\u{201D} with a passphrase, then pick that .rayconfig file.")
            }

        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { accessibilityTrusted = AutoPasteService.isTrusted }
    }

    // MARK: - Helpers

    // MARK: - Maccy import

    private func importFromMaccy() {
        let panel = NSOpenPanel()
        panel.title = "Choose Maccy Folder"
        panel.message = "Select the \u{201C}Maccy\u{201D} folder (or Storage.sqlite inside it)."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = MaccyImporter.defaultFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let count = try MaccyImporter.importClipboard(from: url)
            showImportResult(
                title: count > 0 ? "Import Complete" : "Nothing to Import",
                message: count > 0
                    ? "Added \(count) item\(count == 1 ? "" : "s") from Maccy."
                    : "No new clipboard items were found (they may already be in your history)."
            )
        } catch {
            showImportResult(title: "Import Failed", message: error.localizedDescription, style: .warning)
        }
    }

    // MARK: - Raycast import

    private func importFromRaycast() {
        let panel = NSOpenPanel()
        panel.title = "Choose Raycast Export"
        panel.allowedContentTypes = []
        panel.allowedFileTypes = ["rayconfig"]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let passphrase = promptForPassphrase(), !passphrase.isEmpty else { return }

        do {
            let count = try RaycastImporter.importClipboard(from: url, passphrase: passphrase)
            showImportResult(
                title: count > 0 ? "Import Complete" : "Nothing to Import",
                message: count > 0
                    ? "Added \(count) item\(count == 1 ? "" : "s") from Raycast."
                    : "No new clipboard items were found (they may already be in your history)."
            )
            NotificationCenter.default.post(name: .clipboardDidUpdate, object: nil)
        } catch {
            showImportResult(
                title: "Import Failed",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func promptForPassphrase() -> String? {
        let alert = NSAlert()
        alert.messageText = "Enter Raycast Export Passphrase"
        alert.informativeText = "The passphrase you set when exporting from Raycast."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func showImportResult(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func applyLimit() {
        let store = ClipboardStore.shared
        switch historyLimitOption {
        case .unlimited:
            store.maxHistoryItems = nil
        case .twoHundred:
            store.maxHistoryItems = 200
            store.enforceHistoryLimit()
        case .fiveHundred:
            store.maxHistoryItems = 500
            store.enforceHistoryLimit()
        case .custom:
            if let n = Int(customLimitText.trimmingCharacters(in: .whitespaces)), n > 0 {
                store.maxHistoryItems = n
                store.enforceHistoryLimit()
            }
        }
    }
}
