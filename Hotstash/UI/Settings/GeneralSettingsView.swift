import AppKit
import SwiftUI

// MARK: - GeneralSettingsView

struct GeneralSettingsView: View {

    // MARK: - State

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @State private var historyLimit: Int = {
        let stored = UserDefaults.standard.integer(forKey: "historyLimit")
        return stored > 0 ? stored : 200
    }()
    @State private var hotkeyCode:      UInt32 = HotkeyManager.shared.keyCode
    @State private var hotkeyModifiers: UInt32 = HotkeyManager.shared.modifiers
    @State private var panelPosition: PanelPosition = PanelPosition.current
    @State private var showingClearConfirmation = false

    // MARK: - Supported history limits

    private let historyLimits: [Int] = [50, 100, 200, 500]

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
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Click the shortcut field, then press your desired key combination.")
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
                Picker("History limit", selection: $historyLimit) {
                    ForEach(historyLimits, id: \.self) { limit in
                        Text("\(limit) items").tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: historyLimit) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "historyLimit")
                    Task { @MainActor in
                        ClipboardStore.shared.maxItems = newValue
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

            // MARK: Accessibility

            Section {
                Button("Request Accessibility Permission") {
                    requestAccessibilityPermission()
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Hotstash needs accessibility access to simulate paste when you select a clipboard item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }
}
