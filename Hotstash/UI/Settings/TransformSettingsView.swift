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
                        TransformIconView(icon: row.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)

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
            // Reload each time the tab appears so newly installed / renamed
            // marketplace transforms show their current name (the @State was
            // otherwise captured once and went stale). Also pull any updated
            // manifests from the backend, then reload again if anything changed.
            .onAppear {
                transforms = Self.loadRows()
                syncFromMarketplace()
            }

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

    // MARK: - Marketplace sync

    /// Pulls fresh manifests for installed transforms from the backend and
    /// reloads the rows if any changed. No-op when no backend is configured.
    private func syncFromMarketplace() {
        guard MarketplaceServiceProvider.isConfigured else { return }
        let service = MarketplaceServiceProvider.shared
        Task { @MainActor in
            let changed = await MarketplaceLibrary.shared.syncInstalled(using: service)
            if changed { transforms = Self.loadRows() }
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
