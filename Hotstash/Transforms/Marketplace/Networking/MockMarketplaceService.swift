import Foundation

/// Deterministic in-memory marketplace backend. Used for previews, offline
/// runs, and tests, and as the automatic fallback when no `Supabase.plist` is
/// configured.
struct MockMarketplaceService: MarketplaceService {

    /// Stable sample slugs used by tests.
    static let slugifyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let quoteID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    private static let samples: [TransformDetail] = [
        TransformDetail(
            id: slugifyID, slug: "slugify", name: "Slugify", authorName: "hotstash",
            kind: .text, category: "Cleanup", installCount: 1280, ratingAvg: 4.7,
            ratingCount: 64, isFeatured: true,
            description: "Lowercase and hyphenate text into a URL slug.",
            version: 2,
            body: .text(js: "function transform(input){ return input.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,''); }")
        ),
        TransformDetail(
            id: quoteID, slug: "quote-lines", name: "Quote Lines", authorName: "community",
            kind: .text, category: "Wrap", installCount: 342, ratingAvg: 4.2,
            ratingCount: 18, isFeatured: false,
            description: "Wraps every non-empty line in double quotes.",
            version: 1,
            body: .text(js: "function transform(input){ return input.split('\\n').map(l=>l.trim()).filter(Boolean).map(l=>'\"'+l+'\"').join('\\n'); }")
        ),
    ]

    private static func listItem(_ d: TransformDetail) -> TransformListItem {
        TransformListItem(
            id: d.id, slug: d.slug, name: d.name, authorName: d.authorName,
            kind: d.kind, category: d.category, installCount: d.installCount,
            ratingAvg: d.ratingAvg, ratingCount: d.ratingCount, isFeatured: d.isFeatured
        )
    }

    func featured() async throws -> [TransformListItem] {
        Self.samples.filter { $0.isFeatured }.map(Self.listItem)
    }

    func browse(search: String?, category: String?, sort: MarketplaceSort) async throws -> [TransformListItem] {
        var items = Self.samples
        if let category, !category.isEmpty { items = items.filter { $0.category == category } }
        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            let term = search.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(term) || $0.description.lowercased().contains(term)
            }
        }
        switch sort {
        case .mostInstalled: items.sort { $0.installCount > $1.installCount }
        case .newest:        items.sort { $0.version > $1.version }
        }
        return items.map(Self.listItem)
    }

    func detail(slug: String) async throws -> TransformDetail {
        guard let match = Self.samples.first(where: { $0.slug == slug }) else {
            throw MarketplaceError.message("Not found")
        }
        return match
    }

    func recordInstall(transformID: UUID) async throws {}

    func reviews(transformID: UUID) async throws -> [MarketplaceReview] {
        [
            MarketplaceReview(id: UUID(), authorName: "alex", stars: 5,
                              body: "Use this every day.", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
        ]
    }

    func submit(manifest: TransformManifest, accessToken: String) async throws -> SubmitResult {
        SubmitResult(status: "live", reason: nil)
    }

    func rate(transformID: UUID, stars: Int, accessToken: String) async throws {}
    func postReview(transformID: UUID, body: String, accessToken: String) async throws {}
    func report(targetType: String, targetID: UUID, reason: String, accessToken: String) async throws {}

    func myTransforms(accessToken: String) async throws -> [TransformListItem] {
        [TransformListItem(
            id: Self.slugifyID, slug: "slugify", name: "Slugify", authorName: "you",
            kind: .text, category: "Cleanup", installCount: 1280, ratingAvg: 4.7,
            ratingCount: 64, isFeatured: true, status: "live"
        )]
    }

    func setDisplayName(_ name: String, accessToken: String) async throws {}

    func pendingReview(accessToken: String) async throws -> [TransformListItem] {
        [TransformListItem(
            id: UUID(), slug: "pending-sample", name: "Pending Sample", authorName: "someone",
            kind: .text, category: "Cleanup", installCount: 0, ratingAvg: 0, ratingCount: 0, isFeatured: false
        )]
    }

    func approve(transformID: UUID, accessToken: String) async throws {}
    func reject(transformID: UUID, accessToken: String) async throws {}
}
