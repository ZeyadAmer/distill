import Foundation

/// Abstraction over the marketplace backend. The app talks only to this protocol
/// so the live Supabase implementation and the offline mock are interchangeable.
protocol MarketplaceService {
    /// Featured transforms for the storefront hero.
    func featured() async throws -> [TransformListItem]

    /// Browse live transforms with optional search/category filters and a sort.
    func browse(search: String?, category: String?, sort: MarketplaceSort) async throws -> [TransformListItem]

    /// Full detail (including executable body) for a single transform by slug.
    func detail(slug: String) async throws -> TransformDetail

    /// Increment the install counter for a transform (anonymous-friendly).
    func recordInstall(transformID: UUID) async throws

    /// Reviews for a transform, newest first.
    func reviews(transformID: UUID) async throws -> [MarketplaceReview]

    /// Submit a manifest for publishing/moderation. Requires a signed-in token.
    func submit(manifest: TransformManifest, accessToken: String) async throws -> SubmitResult

    /// Set the current user's star rating (1...5) for a transform.
    func rate(transformID: UUID, stars: Int, accessToken: String) async throws

    /// Post a free-text review for a transform.
    func postReview(transformID: UUID, body: String, accessToken: String) async throws

    /// File an abuse report against a transform or review.
    func report(targetType: String, targetID: UUID, reason: String, accessToken: String) async throws

    /// Transforms owned by the signed-in user, any status (for "My Transforms").
    func myTransforms(accessToken: String) async throws -> [TransformListItem]

    /// Update the signed-in user's public display name.
    func setDisplayName(_ name: String, accessToken: String) async throws

    // MARK: Admin (require is_admin server-side; RLS/RPCs enforce it)

    /// Transforms awaiting review (admin only — RLS returns these only to admins).
    func pendingReview(accessToken: String) async throws -> [TransformListItem]

    /// Approve a pending transform → live (admin RPC).
    func approve(transformID: UUID, accessToken: String) async throws

    /// Reject/remove a transform (admin RPC).
    func reject(transformID: UUID, accessToken: String) async throws
}
