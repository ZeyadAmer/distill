import Foundation

/// Which settings tab is selected. Used so deep links can switch tabs.
enum SettingsTab: Hashable {
    case general, transforms, marketplace, about
}

/// App-wide navigation router. Deep links (`hotstash://transform/<slug>`) set
/// `pendingTransformSlug` and switch to the marketplace tab; the marketplace
/// surface observes the slug and presents that transform's detail.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: SettingsTab = .general
    @Published var pendingTransformSlug: String?

    private init() {}

    /// Routes to a transform from a deep link.
    func openTransform(slug: String) {
        selectedTab = .marketplace
        pendingTransformSlug = slug
    }
}
