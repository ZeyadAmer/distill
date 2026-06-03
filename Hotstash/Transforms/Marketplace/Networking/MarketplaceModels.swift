import Foundation

// MARK: - List Item

/// A lightweight transform row for browse/featured lists. Mirrors the columns
/// selected from the Supabase `transforms` table (plus the joined author name).
struct TransformListItem: Identifiable, Codable, Equatable {
    let id: UUID
    let slug: String
    let name: String
    let authorName: String?
    let kind: TransformKind
    let category: String
    let installCount: Int
    let ratingAvg: Double
    let ratingCount: Int
    let isFeatured: Bool
    /// Server status (pending|live|removed). Populated for "my transforms"; nil for public lists.
    let status: String?

    init(id: UUID, slug: String, name: String, authorName: String?, kind: TransformKind,
         category: String, installCount: Int, ratingAvg: Double, ratingCount: Int,
         isFeatured: Bool, status: String? = nil) {
        self.id = id; self.slug = slug; self.name = name; self.authorName = authorName
        self.kind = kind; self.category = category; self.installCount = installCount
        self.ratingAvg = ratingAvg; self.ratingCount = ratingCount
        self.isFeatured = isFeatured; self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case authorName = "author_name"
        case kind
        case category
        case installCount = "install_count"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case isFeatured = "is_featured"
        case status
    }
}

// MARK: - Detail

/// Full transform detail: all list fields plus the description, current version,
/// and the executable body assembled from the latest `transform_versions` row.
struct TransformDetail: Identifiable, Codable, Equatable {
    let id: UUID
    let slug: String
    let name: String
    let authorName: String?
    let kind: TransformKind
    let category: String
    let installCount: Int
    let ratingAvg: Double
    let ratingCount: Int
    let isFeatured: Bool
    let description: String
    let version: Int
    let body: TransformBody

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case authorName = "author_name"
        case kind
        case category
        case installCount = "install_count"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case isFeatured = "is_featured"
        case description
        case version
        case body
    }

    /// Returns a copy with the author name set (the detail query fills this in
    /// from the owner's profile after the main fetch).
    func withAuthor(_ name: String) -> TransformDetail {
        TransformDetail(
            id: id, slug: slug, name: self.name, authorName: name, kind: kind,
            category: category, installCount: installCount, ratingAvg: ratingAvg,
            ratingCount: ratingCount, isFeatured: isFeatured, description: description,
            version: version, body: body
        )
    }

    /// Builds a `TransformManifest` suitable for local install/execution.
    func toManifest() -> TransformManifest {
        TransformManifest(
            id: id,
            slug: slug,
            version: version,
            kind: kind,
            name: name,
            description: description,
            icon: kind == .image ? "photo" : "textformat",
            category: category,
            authorName: authorName,
            body: body
        )
    }
}

// MARK: - Review

/// A free-text review row joined with its author's display name.
struct MarketplaceReview: Identifiable, Codable, Equatable {
    let id: UUID
    let authorName: String?
    let stars: Int?
    let body: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case authorName = "author_name"
        case stars
        case body
        case createdAt = "created_at"
    }
}

// MARK: - Sort

/// Browse sort order, mapped to PostgREST `order=` clauses by the service.
enum MarketplaceSort: String {
    case mostInstalled
    case newest
}

// MARK: - Submit Result

/// Result returned by the `submit` Edge Function. `status` is one of
/// `pending` | `live` | `rejected`; `reason` is populated when rejected.
struct SubmitResult: Codable, Equatable {
    let status: String
    let reason: String?
}

// MARK: - Errors

/// Errors surfaced by the marketplace networking layer.
enum MarketplaceError: Error, Equatable {
    case notConfigured
    case notSignedIn
    case http(Int)
    case decoding
    case message(String)
}

extension MarketplaceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Marketplace backend not configured."
        case .notSignedIn:   return "You're not signed in."
        case .http(let code): return "Network error (\(code))."
        case .decoding:      return "Couldn't read the server response."
        case .message(let m): return m
        }
    }
}
