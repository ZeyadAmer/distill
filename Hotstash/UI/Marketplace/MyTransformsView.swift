import SwiftUI
import UniformTypeIdentifiers

// MARK: - MyTransformsView

/// Manages the user's local drafts and installed transforms: create, import,
/// edit, delete, and publish.
struct MyTransformsView: View {

    /// Optional signed-in token. Publish requires one; nil → prompt to sign in.
    /// Sourced from `AuthManager.shared.accessToken` (stub until S4).
    var accessToken: String?

    let service: MarketplaceService

    @State private var drafts: [StoredTransform] = []
    @State private var installed: [StoredTransform] = []
    @State private var published: [TransformListItem] = []   // owned on the server
    @State private var builderMode: BuilderMode?
    @State private var statusMessage: String?

    init(accessToken: String? = nil, service: MarketplaceService = MarketplaceServiceProvider.shared) {
        self.accessToken = accessToken
        self.service = service
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            list
            if let statusMessage {
                Divider()
                Text(statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .onAppear(perform: reload)
        .task(id: accessToken) { await loadPublished() }
        .sheet(item: $builderMode, onDismiss: reload) { mode in
            TransformBuilderView(editing: mode.manifest)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack {
            Button {
                builderMode = .new
            } label: {
                Label("New Transform", systemImage: "plus")
            }
            Button {
                importTransform()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            Spacer()
        }
        .padding(12)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if drafts.isEmpty && installed.isEmpty && published.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
                Text("No transforms yet. Create or import one.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                // Local drafts NOT yet on the server (published ones live under
                // "Published by you" to avoid showing the same transform twice).
                let unpublished = drafts.filter { draft in
                    !published.contains { $0.slug == draft.slug }
                }
                if !unpublished.isEmpty {
                    Section("Drafts") {
                        ForEach(unpublished, id: \.slug) { row in draftRow(row) }
                    }
                }
                if !published.isEmpty {
                    Section("Published by you") {
                        ForEach(published) { item in publishedRow(item) }
                    }
                }
                if !installed.isEmpty {
                    Section("Installed") {
                        ForEach(installed, id: \.slug) { row in installedRow(row) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    /// Real status for a local draft: prefer the authoritative server status
    /// (from "Published by you"), else local draft/submitted state.
    private func statusLabel(for row: StoredTransform) -> String {
        if let serverStatus = published.first(where: { $0.slug == row.slug })?.status {
            switch serverStatus {
            case "pending": return "in review"
            case "live":    return "live"
            case "removed": return "removed"
            default:        return serverStatus
            }
        }
        return row.isPublished ? "submitted" : "draft"
    }

    /// A transform the signed-in user owns on the server (survives local delete).
    private func publishedRow(_ item: TransformListItem) -> some View {
        HStack(spacing: 10) {
            rowLabelText(name: item.name, status: item.status ?? "live")
            Spacer()
            Button("Edit") { Task { await editPublished(item) } }
        }
    }

    private func editPublished(_ item: TransformListItem) async {
        do {
            let detail = try await service.detail(slug: item.slug)
            builderMode = .edit(detail.toManifest())
        } catch {
            // detail() only returns live rows; for pending/removed, edit the local draft if present.
            if let local = MarketplaceLibrary.shared.stored(slug: item.slug)?.manifest {
                builderMode = .edit(local)
            } else {
                statusMessage = "Can't edit \(item.name) yet (status: \(item.status ?? "unknown"))."
            }
        }
    }

    private func loadPublished() async {
        guard let token = accessToken else { published = []; return }
        published = (try? await service.myTransforms(accessToken: token)) ?? []
    }

    private func draftRow(_ row: StoredTransform) -> some View {
        HStack(spacing: 10) {
            rowLabel(row, status: statusLabel(for: row))
            Spacer()
            Button("Edit") {
                if let manifest = row.manifest { builderMode = .edit(manifest) }
            }
            // Always allow (re)publishing: returning authors push updates as new versions.
            Button(row.isPublished ? "Update" : "Publish") {
                Task { await publish(row) }
            }
            Button(role: .destructive) {
                MarketplaceLibrary.shared.delete(slug: row.slug)
                reload()
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private func installedRow(_ row: StoredTransform) -> some View {
        HStack(spacing: 10) {
            rowLabel(row, status: "installed")
            Spacer()
            Button(role: .destructive) {
                MarketplaceLibrary.shared.delete(slug: row.slug)
                reload()
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private func rowLabel(_ row: StoredTransform, status: String) -> some View {
        let manifest = row.manifest
        return HStack(spacing: 10) {
            Image(systemName: manifest?.icon ?? "wand.and.stars")
                .foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(manifest?.name ?? row.slug).font(.body)
                Text(status).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func rowLabelText(name: String, status: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body)
                Text(status).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Actions

    private func reload() {
        drafts = MarketplaceLibrary.shared.localDrafts()
        installed = MarketplaceLibrary.shared.installed()
        Task { await loadPublished() }
    }

    private func importTransform() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: MarketplaceLibrary.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try MarketplaceLibrary.shared.importManifest(from: data)
            MarketplaceLibrary.shared.upsert(manifest: manifest, origin: "local")
            statusMessage = "Imported \(manifest.name)."
            reload()
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func publish(_ row: StoredTransform) async {
        guard let manifest = row.manifest else {
            statusMessage = "Couldn't read this draft."
            return
        }
        guard let accessToken else {
            statusMessage = "Sign in to publish transforms."
            return
        }
        do {
            let result = try await service.submit(manifest: manifest, accessToken: accessToken)
            if result.status == "rejected" {
                statusMessage = "Rejected: \(result.reason ?? "no reason given")"
            } else {
                MarketplaceLibrary.shared.setPublished(slug: row.slug, true)
                statusMessage = "Submitted (\(result.status))."
                reload()
            }
        } catch {
            statusMessage = "Publish failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - BuilderMode

/// Drives the builder sheet via `.sheet(item:)` so the correct manifest is
/// always passed (avoids the stale-capture bug of a separate isPresented flag).
enum BuilderMode: Identifiable {
    case new
    case edit(TransformManifest)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let manifest): return manifest.id.uuidString
        }
    }

    /// The manifest to edit, or nil for a new transform.
    var manifest: TransformManifest? {
        switch self {
        case .new: return nil
        case .edit(let manifest): return manifest
        }
    }
}
