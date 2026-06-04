import SwiftUI

// MARK: - QuickTransformsSettingsView

/// Lets the user map up to five global hotkeys to a transform that is applied to
/// the clipboard and pasted straight into the focused app (e.g. ⌘G → Uppercase).
struct QuickTransformsSettingsView: View {

    @StateObject private var store = QuickTransformStore.shared

    /// Working copy of the slots; committed to the store on each change.
    @State private var slots: [QuickTransformSlot] = QuickTransformStore.shared.slots

    /// Text-only transforms offered in the picker (image transforms can't be
    /// applied to clipboard text).
    private let transformChoices: [(id: String, name: String)] = TransformRegistry.shared.orderedAll
        .filter { $0.category != .image }
        .map { (id: $0.id, name: $0.name) }

    var body: some View {
        Section {
            ForEach(slots.indices, id: \.self) { index in
                slotRow(index)
            }
        } header: {
            Text("Quick Transforms")
        } footer: {
            Text("Each shortcut applies a transform to whatever is on the clipboard and pastes the result into the focused app. Requires Accessibility permission to paste automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func slotRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { slots[index].isEnabled },
                set: { newValue in
                    slots[index].isEnabled = newValue
                    commit(index)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Picker("", selection: Binding(
                get: { slots[index].transformID },
                set: { newValue in
                    slots[index].transformID = newValue
                    commit(index)
                }
            )) {
                ForEach(transformChoices, id: \.id) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            HotkeyRecorderView(
                keyCode: Binding(
                    get: { slots[index].keyCode },
                    set: { slots[index].keyCode = $0 }
                ),
                modifiers: Binding(
                    get: { slots[index].modifiers },
                    set: { slots[index].modifiers = $0 }
                ),
                commit: { code, mods in
                    slots[index].keyCode = code
                    slots[index].modifiers = mods
                    // Recording a shortcut implies the user wants it on.
                    slots[index].isEnabled = true
                    commit(index)
                }
            )
            .frame(width: 110)
        }
        .opacity(slots[index].isEnabled ? 1 : 0.5)
    }

    // MARK: - Commit

    private func commit(_ index: Int) {
        store.update(slots[index])
    }
}
