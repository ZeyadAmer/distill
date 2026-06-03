import Foundation

/// Resolves the marketplace backend for the running app: the live Supabase
/// service when `Supabase.plist` is configured, otherwise the offline mock.
/// This lets the whole UI build and run before any backend exists.
enum MarketplaceServiceProvider {
    static var shared: MarketplaceService {
        if let config = SupabaseConfig.current {
            return SupabaseMarketplaceService(config: config)
        }
        return MockMarketplaceService()
    }

    /// True when a real backend is configured (UI can show "offline" affordances otherwise).
    static var isConfigured: Bool { SupabaseConfig.current != nil }
}
