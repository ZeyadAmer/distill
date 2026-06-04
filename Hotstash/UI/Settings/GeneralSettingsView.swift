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

            // MARK: Direct paste

            Section {
                LabeledContent("Paste into focused app") {
                    if accessibilityTrusted {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("Enable\u{2026}") {
                            _ = AutoPasteService.requestPermissionIfNeeded()
                            AutoPasteService.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("Direct Paste")
            } footer: {
                Text("When enabled, pressing Return or double-clicking an item pastes it straight into the app you were using. This needs Accessibility permission in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { accessibilityTrusted = AutoPasteService.isTrusted }
    }

    // MARK: - Helpers

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
