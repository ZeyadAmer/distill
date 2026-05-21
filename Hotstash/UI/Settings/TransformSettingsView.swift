import SwiftUI

// MARK: - TransformSettingsView

struct TransformSettingsView: View {

    // MARK: - State

    /// The set of transform IDs that are currently disabled.
    @State private var disabledIDs: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: "disabledTransformIDs") ?? []
        return Set(stored)
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(TransformCategory.allCases, id: \.self) { category in
                    let transforms = TransformRegistry.shared.transforms(in: category)
                    if !transforms.isEmpty {
                        Section(category.rawValue) {
                            ForEach(transforms, id: \.id) { transform in
                                transformRow(transform)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            Text("Disabled transforms are hidden from the picker and suggestions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func transformRow(_ transform: any Transform) -> some View {
        let isEnabled = Binding<Bool>(
            get: { !disabledIDs.contains(transform.id) },
            set: { enabled in
                if enabled {
                    disabledIDs.remove(transform.id)
                } else {
                    disabledIDs.insert(transform.id)
                }
                persistDisabledIDs()
            }
        )

        Toggle(isOn: isEnabled) {
            Label {
                Text(transform.name)
            } icon: {
                Image(systemName: transform.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Persistence

    private func persistDisabledIDs() {
        let array = Array(disabledIDs)
        UserDefaults.standard.set(array, forKey: "disabledTransformIDs")
    }
}
