import SwiftUI

// MARK: - TransformOrderView

/// Drag-to-reorder + enable/disable list for the built-in transforms,
/// mirroring the Mac app's Transforms settings. The saved order drives the
/// keyboard's transform strip and every transform picker.
struct TransformOrderView: View {

    private struct Row: Identifiable {
        let id: String
        let name: String
        let icon: String
    }

    @State private var rows: [Row] = []
    @State private var enabled: [String: Bool] = [:]

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        TransformIconView(icon: row.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 24, height: 24)
                        Text(row.name)
                        Spacer()
                        Toggle("", isOn: binding(for: row.id))
                            .labelsHidden()
                    }
                }
                .onMove { from, to in
                    rows.move(fromOffsets: from, toOffset: to)
                    IOSTransformSettings.saveOrder(rows.map(\.id))
                }
            } footer: {
                Text("Drag to reorder, toggle to enable. The keyboard and transform pickers follow this order.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .onAppear(perform: refresh)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { enabled[id] ?? true },
            set: { newValue in
                enabled[id] = newValue
                IOSTransformSettings.setEnabled(id, newValue)
            }
        )
    }

    private func refresh() {
        let ordered = IOSTransformSettings.orderedAll()
        rows = ordered.map { Row(id: $0.id, name: $0.name, icon: $0.icon) }
        enabled = Dictionary(ordered.map { ($0.id, IOSTransformSettings.isEnabled($0.id)) },
                             uniquingKeysWith: { first, _ in first })
    }
}
