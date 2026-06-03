import Foundation

/// Live marketplace backend over Supabase (PostgREST + Edge Functions).
///
/// All requests carry the `apikey` header (anon key) and an `Authorization`
/// bearer (anon key for public reads, the user's access token for writes).
/// Reads rely on RLS exposing only `status = 'live'` rows.
struct SupabaseMarketplaceService: MarketplaceService {

    let config: SupabaseConfig
    private let session: URLSession

    init(config: SupabaseConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Decoders

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Public reads

    func featured() async throws -> [TransformListItem] {
        let q = "transforms?status=eq.live&is_featured=eq.true&select=\(Self.listColumns)&order=install_count.desc&limit=20"
        return try await getList(q)
    }

    func browse(search: String?, category: String?, sort: MarketplaceSort) async throws -> [TransformListItem] {
        var parts = ["status=eq.live", "select=\(Self.listColumns)"]
        if let category, !category.isEmpty { parts.append("category=eq.\(escape(category))") }
        if let search, !search.trimmingCharacters(in: .whitespaces).isEmpty {
            let term = escape("*\(search)*")
            parts.append("or=(name.ilike.\(term),description.ilike.\(term))")
        }
        switch sort {
        case .mostInstalled: parts.append("order=install_count.desc")
        case .newest:        parts.append("order=created_at.desc")
        }
        parts.append("limit=100")
        return try await getList("transforms?" + parts.joined(separator: "&"))
    }

    func detail(slug: String) async throws -> TransformDetail {
        // Fetch the row + its newest version body in a single embedded query.
        let q = "transforms?slug=eq.\(escape(slug))&status=eq.live"
            + "&select=id,slug,name,description,kind,category,latest_version,install_count,rating_avg,rating_count,is_featured,transform_versions(version,body)"
            + "&transform_versions.order=version.desc&transform_versions.limit=1"
        let rows: [DetailRow] = try await get(q)
        guard let row = rows.first, let detail = row.toDetail() else { throw MarketplaceError.decoding }
        return detail
    }

    func recordInstall(transformID: UUID) async throws {
        try await rpc("record_install", body: ["p_transform_id": transformID.uuidString])
    }

    func reviews(transformID: UUID) async throws -> [MarketplaceReview] {
        let q = "reviews?transform_id=eq.\(transformID.uuidString)&status=eq.live"
            + "&select=id,body,created_at&order=created_at.desc&limit=100"
        // author_name + stars are optional in the DTO; omitted here (no join) → nil.
        return (try? await getReviews(q)) ?? []
    }

    // MARK: Authenticated writes

    func submit(manifest: TransformManifest, accessToken: String) async throws -> SubmitResult {
        let body = try TransformManifestCodec.encode(manifest)
        var req = try request(path: "/functions/v1/submit", method: "POST", token: accessToken)
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        try Self.checkStatus(response)
        guard let result = try? Self.decoder.decode(SubmitResult.self, from: data) else {
            throw MarketplaceError.decoding
        }
        return result
    }

    func rate(transformID: UUID, stars: Int, accessToken: String) async throws {
        guard let profileID = Self.subject(fromJWT: accessToken) else { throw MarketplaceError.notSignedIn }
        // Upsert (one rating per (transform, profile)).
        let payload: [String: Any] = [
            "transform_id": transformID.uuidString,
            "profile_id": profileID,
            "stars": stars,
        ]
        try await postTable("ratings", payload: payload, token: accessToken,
                            prefer: "resolution=merge-duplicates")
    }

    func postReview(transformID: UUID, body: String, accessToken: String) async throws {
        guard let profileID = Self.subject(fromJWT: accessToken) else { throw MarketplaceError.notSignedIn }
        try await postTable("reviews", payload: [
            "transform_id": transformID.uuidString,
            "profile_id": profileID,
            "body": body,
        ], token: accessToken)
    }

    func report(targetType: String, targetID: UUID, reason: String, accessToken: String) async throws {
        guard let profileID = Self.subject(fromJWT: accessToken) else { throw MarketplaceError.notSignedIn }
        try await postTable("reports", payload: [
            "target_type": targetType,
            "target_id": targetID.uuidString,
            "reporter_id": profileID,
            "reason": reason,
        ], token: accessToken)
    }

    // MARK: - Private helpers

    private static let listColumns =
        "id,slug,name,kind,category,install_count,rating_avg,rating_count,is_featured"

    private func getList(_ query: String) async throws -> [TransformListItem] {
        try await get(query)
    }

    private func getReviews(_ query: String) async throws -> [MarketplaceReview] {
        try await get(query)
    }

    private func get<T: Decodable>(_ query: String) async throws -> T {
        let req = try request(path: "/rest/v1/\(query)", method: "GET", token: config.anonKey)
        let (data, response) = try await session.data(for: req)
        try Self.checkStatus(response)
        guard let decoded = try? Self.decoder.decode(T.self, from: data) else {
            throw MarketplaceError.decoding
        }
        return decoded
    }

    private func rpc(_ name: String, body: [String: String]) async throws {
        var req = try request(path: "/rest/v1/rpc/\(name)", method: "POST", token: config.anonKey)
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: req)
        try Self.checkStatus(response)
    }

    private func postTable(_ table: String, payload: [String: Any], token: String,
                           prefer: String? = nil) async throws {
        var req = try request(path: "/rest/v1/\(table)", method: "POST", token: token)
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await session.data(for: req)
        try Self.checkStatus(response)
    }

    private func request(path: String, method: String, token: String) throws -> URLRequest {
        guard let url = URL(string: config.url.absoluteString + path) else {
            throw MarketplaceError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw MarketplaceError.http(http.statusCode)
        }
    }

    /// Strict escaping for PostgREST filter values. `.urlQueryAllowed` leaves
    /// `(`, `)`, `,`, `&`, `*`, `=` unencoded — all structurally meaningful in
    /// PostgREST syntax — which would let a crafted search term/slug inject
    /// extra filter params. Encode everything except RFC 3986 unreserved chars.
    private static let postgrestSafeChars: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.postgrestSafeChars) ?? value
    }

    /// Extracts the `sub` (user id) claim from a JWT without verifying it
    /// (verification happens server-side; we only need the id for write payloads).
    static func subject(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String else { return nil }
        return sub
    }
}

// MARK: - Private decoding shapes

/// The embedded detail query returns the transform row plus a nested
/// `transform_versions` array (newest first, limited to 1).
private struct DetailRow: Decodable {
    let id: UUID
    let slug: String
    let name: String
    let description: String
    let kind: TransformKind
    let category: String
    let latest_version: Int
    let install_count: Int
    let rating_avg: Double
    let rating_count: Int
    let is_featured: Bool
    let transform_versions: [VersionRow]

    struct VersionRow: Decodable {
        let version: Int
        let body: TransformBody
    }

    func toDetail() -> TransformDetail? {
        guard let body = transform_versions.first?.body else { return nil }
        return TransformDetail(
            id: id, slug: slug, name: name, authorName: nil, kind: kind,
            category: category, installCount: install_count, ratingAvg: rating_avg,
            ratingCount: rating_count, isFeatured: is_featured,
            description: description, version: latest_version, body: body
        )
    }
}
