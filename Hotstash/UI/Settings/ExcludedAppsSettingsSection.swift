import SwiftUI

// MARK: - ExcludedAppsSettingsSection

/// Settings section listing apps whose copies Hotstash never records.
/// Apps are added from the currently-running list or by typing a bundle id.
struct ExcludedAppsSettingsSection: View {

    @State private var excluded: [String] = []
    @State private var manualBundleID: String = ""

    var body: some View {
        Section {
            if excluded.isEmpty {
                Text("No apps excluded. Copies from every app are recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(excluded, id: \.self) { bundleID in
                ExcludedAppRow(bundleID: bundleID) {
                    ExclusionList.shared.remove(bundleID: bundleID)
                    refresh()
                }
            }

            Menu("Add Running App") {
                ForEach(ExclusionList.shared.candidateRunningApps(), id: \.bundleID) { app in
                    Button {
                        ExclusionList.shared.add(bundleID: app.bundleID)
                        refresh()
                    } label: {
                        if let icon = app.icon {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: icon)
                            }
                        } else {
                            Text(app.name)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Or type a bundle id, e.g. com.apple.Terminal", text: $manualBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addManual)
                Button("Add", action: addManual)
                    .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("Anything you copy while one of these apps is in front is never saved to your history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
    }

    private func addManual() {
        ExclusionList.shared.add(bundleID: manualBundleID)
        manualBundleID = ""
        refresh()
    }

    private func refresh() {
        excluded = ExclusionList.shared.excludedBundleIDs
    }
}

// MARK: - ExcludedAppRow

private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        let info = ExclusionList.shared.displayInfo(for: bundleID)
        HStack {
            if let icon = info.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from exclusion list")
        }
    }
}
