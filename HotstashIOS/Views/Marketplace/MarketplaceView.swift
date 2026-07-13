import SwiftUI

// MARK: - MarketplaceView

/// iOS storefront for community transforms. Reuses the Mac app's
/// `MarketplaceViewModel` (pure Foundation) over the same Supabase backend;
/// installs land in the shared SwiftData store and sync across devices.
struct MarketplaceView: View {

    @StateObject private var viewModel = MarketplaceViewModel()
    /// 0 = Featured, 1 = Browse, 2 = Installed.
    @State private var tab = 0
    @State private var installedRefresh = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                Text("Featured").tag(0)
                Text("Browse").tag(1)
                Text("Installed").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch tab {
            case 0: featuredList
            case 1: browseList
            default: installedList
            }
        }
        .navigationTitle("Marketplace")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.refreshInstalled()
            await viewModel.load()
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.caption)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
    }

    // MARK: Featured

    private var featuredList: some View {
        List {
            if viewModel.featured.isEmpty && !viewModel.isLoading {
                Text("Nothing featured right now.")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.featured) { item in
                MarketplaceRow(item: item, viewModel: viewModel)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }

    // MARK: Browse

    private var browseList: some View {
        List {
            ForEach(viewModel.results) { item in
                MarketplaceRow(item: item, viewModel: viewModel)
            }
            if viewModel.results.isEmpty && !viewModel.isLoading {
                Text("No transforms match.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $viewModel.searchText, prompt: "Search transforms")
        .task(id: viewModel.searchText) {
            // Small debounce so we don't hit the backend per keystroke.
            try? await Task.sleep(nanoseconds: 300_000_000)
            await viewModel.search()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Most Installed") {
                        viewModel.sort = .mostInstalled
                        Task { await viewModel.search() }
                    }
                    Button("Newest") {
                        viewModel.sort = .newest
                        Task { await viewModel.search() }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    // MARK: Installed

    private var installedList: some View {
        List {
            let installed = MarketplaceLibrary.shared.customTransforms()
            if installed.isEmpty {
                Text("No installed transforms yet. Install from Featured or Browse — they sync to your Mac too.")
                    .foregroundStyle(.secondary)
            }
            ForEach(installed, id: \.id) { transform in
                HStack(spacing: 12) {
                    TransformIconView(icon: transform.icon)
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transform.name)
                        Text(transform.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.uninstall(slug: transform.id)
                        installedRefresh += 1
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.insetGrouped)
        .id(installedRefresh)
    }
}

// MARK: - MarketplaceRow

private struct MarketplaceRow: View {
    let item: TransformListItem
    @ObservedObject var viewModel: MarketplaceViewModel

    @State private var isInstalling = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(item.category)
                    if let author = item.authorName {
                        Text("by \(author)")
                    }
                    Label("\(item.installCount)", systemImage: "arrow.down.circle")
                    if item.ratingCount > 0 {
                        Label(String(format: "%.1f", item.ratingAvg), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isInstalled(item.slug) {
                Text("Installed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    isInstalling = true
                    Task {
                        await viewModel.install(item)
                        isInstalling = false
                    }
                } label: {
                    if isInstalling {
                        ProgressView()
                    } else {
                        Text("Get")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 2)
    }
}
