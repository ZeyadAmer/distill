import SwiftUI

// MARK: - MarketplaceView

/// The marketplace storefront: search, filters, a featured row, and a results list.
/// Tapping a row presents `TransformDetailView` as a sheet.
struct MarketplaceView: View {

    @StateObject private var viewModel = MarketplaceViewModel()
    @State private var selectedItem: TransformListItem?

    /// Optional signed-in token passed through to the detail sheet.
    /// Wired to `AuthManager.shared.accessToken` in Commit 5.
    var accessToken: String?

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            resultsArea
        }
        .task { await viewModel.load() }
        .sheet(item: $selectedItem) { item in
            TransformDetailView(item: item, viewModel: viewModel, accessToken: accessToken)
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transforms…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await viewModel.search() } }
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("All").tag(String?.none)
                    ForEach(TransformCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(String?.some(category.rawValue))
                    }
                }
                .labelsHidden()
                .onChange(of: viewModel.selectedCategory) { _ in
                    Task { await viewModel.search() }
                }

                Picker("Sort", selection: $viewModel.sort) {
                    Text("Most installed").tag(MarketplaceSort.mostInstalled)
                    Text("Newest").tag(MarketplaceSort.newest)
                }
                .labelsHidden()
                .onChange(of: viewModel.sort) { _ in
                    Task { await viewModel.search() }
                }

                Spacer()
            }
        }
        .padding(12)
    }

    // MARK: Results

    @ViewBuilder
    private var resultsArea: some View {
        if viewModel.isLoading && viewModel.results.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            messageState(icon: "exclamationmark.triangle", text: error)
        } else if viewModel.results.isEmpty && viewModel.featured.isEmpty {
            messageState(icon: "tray", text: "No transforms found.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !viewModel.featured.isEmpty {
                        sectionHeader("Featured")
                        ForEach(viewModel.featured) { item in
                            row(item)
                        }
                        sectionHeader("Browse")
                    }
                    ForEach(viewModel.results) { item in
                        row(item)
                    }
                }
                .padding(12)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption).bold()
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private func row(_ item: TransformListItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.kind == .image ? "photo" : "textformat")
                    .foregroundStyle(.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.body)
                    HStack(spacing: 6) {
                        if let author = item.authorName {
                            Text(author).font(.caption).foregroundStyle(.secondary)
                        }
                        CategoryBadge(text: item.category)
                        CategoryBadge(text: item.kind.rawValue)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f", item.ratingAvg))
                    }
                    .font(.caption)
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                        Text("\(item.installCount)")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }

                if viewModel.isInstalled(item.slug) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func messageState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
