import Foundation

// MARK: - MarketplaceViewModel

/// Drives the storefront: featured + browse results, filters, and install state.
///
/// All networking is funnelled through `MarketplaceServiceProvider.shared`,
/// wrapped in `do/catch` so a backend failure never crashes the UI — it surfaces
/// as `errorMessage`. Works fully against the offline mock with no backend.
@MainActor
final class MarketplaceViewModel: ObservableObject {

    // MARK: Published state

    @Published var featured: [TransformListItem] = []
    @Published var results: [TransformListItem] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: String?
    @Published var sort: MarketplaceSort = .mostInstalled
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var installedSlugs: Set<String> = []

    // MARK: Dependencies

    let service: MarketplaceService

    init(service: MarketplaceService = MarketplaceServiceProvider.shared) {
        self.service = service
    }

    // MARK: Loading

    /// Fetch featured + browse and refresh installed slugs.
    func load() async {
        isLoading = true
        errorMessage = nil
        refreshInstalled()
        do {
            async let featuredItems = service.featured()
            async let browseItems = service.browse(
                search: trimmedSearch,
                category: selectedCategory,
                sort: sort
            )
            featured = try await featuredItems
            results = try await browseItems
        } catch {
            errorMessage = Self.describe(error)
        }
        isLoading = false
    }

    /// Re-run browse with the current filters.
    func search() async {
        isLoading = true
        errorMessage = nil
        do {
            results = try await service.browse(
                search: trimmedSearch,
                category: selectedCategory,
                sort: sort
            )
        } catch {
            errorMessage = Self.describe(error)
        }
        isLoading = false
    }

    // MARK: Install / uninstall

    /// Install `item`: fetch detail, persist its manifest, record the install,
    /// and mark it installed locally.
    func install(_ item: TransformListItem) async {
        errorMessage = nil
        do {
            let detail = try await service.detail(slug: item.slug)
            MarketplaceLibrary.shared.upsert(
                manifest: detail.toManifest(),
                origin: "installed",
                installedVersion: detail.version
            )
            try? await service.recordInstall(transformID: item.id)
            installedSlugs.insert(item.slug)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Remove a locally-installed transform.
    func uninstall(slug: String) {
        MarketplaceLibrary.shared.delete(slug: slug)
        installedSlugs.remove(slug)
    }

    func isInstalled(_ slug: String) -> Bool {
        installedSlugs.contains(slug)
    }

    // MARK: Helpers

    /// Re-read installed slugs from the local library.
    func refreshInstalled() {
        installedSlugs = Set(MarketplaceLibrary.shared.installed().map(\.slug))
    }

    private var trimmedSearch: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func describe(_ error: Error) -> String {
        if let marketplaceError = error as? MarketplaceError {
            switch marketplaceError {
            case .notConfigured: return "Marketplace is not configured."
            case .notSignedIn: return "Please sign in to continue."
            case let .http(code): return "Network error (\(code))."
            case .decoding: return "Couldn't read the server response."
            case let .message(message): return message
            }
        }
        return error.localizedDescription
    }
}
