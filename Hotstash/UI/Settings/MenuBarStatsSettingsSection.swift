import SwiftUI

// MARK: - MenuBarStatsSettingsSection

/// Lets the user pick which system stats show next to the menu bar icon.
struct MenuBarStatsSettingsSection: View {

    @State private var selected: Set<MenuBarStatKind> = Set(MenuBarStatsPreference.selected)

    var body: some View {
        Section {
            ForEach(MenuBarStatKind.allCases) { kind in
                Toggle(kind.label, isOn: binding(for: kind))
            }
        } header: {
            Text("Menu Bar Stats")
        } footer: {
            Text("Shown next to the menu bar icon, in this order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for kind: MenuBarStatKind) -> Binding<Bool> {
        Binding(
            get: { selected.contains(kind) },
            set: { isOn in
                if isOn {
                    selected.insert(kind)
                } else {
                    selected.remove(kind)
                }
                MenuBarStatsPreference.selected = MenuBarStatKind.allCases.filter(selected.contains)
            }
        )
    }
}
