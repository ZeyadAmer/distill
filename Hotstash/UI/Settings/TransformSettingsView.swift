import SwiftUI

// MARK: - TransformSettingsView

struct TransformSettingsView: View {

    // MARK: - State

    @State private var transforms: [TransformRow] = TransformSettingsView.loadRows()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($transforms, id: \.id) { $row in
                    HStack(spacing: 10) {
                        Image(systemName: row.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name)
                                .font(.body)
                            Text(row.categoryName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Toggle("", isOn: $row.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: row.isEnabled) { _ in
                                persistEnabled()
                            }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    transforms.move(fromOffsets: from, toOffset: to)
                    persistOrder()
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text("Drag rows to reorder · Toggle to enable/disable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Persistence

    private func persistOrder() {
        TransformRegistry.shared.saveOrder(transforms.map { $0.id })
    }

    private func persistEnabled() {
        let disabled = transforms.filter { !$0.isEnabled }.map { $0.id }
        UserDefaults.standard.set(disabled, forKey: "disabledTransformIDs")
    }

    // MARK: - Row model

    struct TransformRow: Identifiable {
        let id:           String
        let name:         String
        let icon:         String
        let categoryName: String
        var isEnabled:    Bool
    }

    private static func loadRows() -> [TransformRow] {
        let registry    = TransformRegistry.shared
        let disabledIDs = Set(UserDefaults.standard.stringArray(forKey: "disabledTransformIDs") ?? [])
        return registry.orderedAll.map { t in
            TransformRow(
                id:           t.id,
                name:         t.name,
                icon:         t.icon,
                categoryName: t.category.rawValue,
                isEnabled:    !disabledIDs.contains(t.id)
            )
        }
    }
}
