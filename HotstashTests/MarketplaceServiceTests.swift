import Testing
import Foundation
@testable import Hotstash

struct MarketplaceServiceTests {

    // MARK: DTO decoding

    @Test func listItemDecodesSnakeCase() throws {
        let json = """
        [{"id":"00000000-0000-0000-0000-0000000000A1","slug":"slugify","name":"Slugify",
          "kind":"text","category":"Cleanup","install_count":1280,"rating_avg":4.7,
          "rating_count":64,"is_featured":true}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([TransformListItem].self, from: json)
        #expect(items.count == 1)
        let item = items[0]
        #expect(item.slug == "slugify")
        #expect(item.kind == .text)
        #expect(item.installCount == 1280)
        #expect(item.ratingAvg == 4.7)
        #expect(item.isFeatured == true)
        #expect(item.authorName == nil)   // absent key → nil
    }

    @Test func detailToManifestMapsKindAndBody() {
        let detail = TransformDetail(
            id: UUID(), slug: "slugify", name: "Slugify", authorName: "me",
            kind: .text, category: "Cleanup", installCount: 1, ratingAvg: 5, ratingCount: 1,
            isFeatured: false, description: "d", version: 3,
            body: .text(js: "function transform(i){return i}")
        )
        let manifest = detail.toManifest()
        #expect(manifest.kind == .text)
        #expect(manifest.slug == "slugify")
        #expect(manifest.version == 3)
        if case .text(let js) = manifest.body { #expect(js.contains("transform")) }
        else { Issue.record("expected text body") }
    }

    @Test func transformBodyImageDecodes() throws {
        let json = #"{"steps":[{"type":"grayscale"},{"type":"resize","params":{"scale":0.5}}]}"#.data(using: .utf8)!
        let body = try JSONDecoder().decode(TransformBody.self, from: json)
        if case .image(let steps) = body {
            #expect(steps.count == 2)
            #expect(steps[0].type == "grayscale")
            #expect(steps[1].params["scale"]?.doubleValue == 0.5)
        } else { Issue.record("expected image body") }
    }

    // MARK: Mock

    @Test func mockReturnsDeterministicData() async throws {
        let mock = MockMarketplaceService()
        let featured = try await mock.featured()
        #expect(!featured.isEmpty)
        let all = try await mock.browse(search: nil, category: nil, sort: .mostInstalled)
        #expect(all.count >= 2)
        // most-installed sort: first has the highest install count.
        #expect(all.first!.installCount >= all.last!.installCount)
        let detail = try await mock.detail(slug: "slugify")
        #expect(detail.slug == "slugify")
        let result = try await mock.submit(manifest: detail.toManifest(), accessToken: "t")
        #expect(result.status == "live")
    }

    @Test func mockBrowseSearchFilters() async throws {
        let mock = MockMarketplaceService()
        let hits = try await mock.browse(search: "slug", category: nil, sort: .newest)
        #expect(hits.allSatisfy { $0.name.lowercased().contains("slug") || $0.slug.contains("slug") })
    }

    // MARK: Config + provider

    @Test func configMakeRejectsPlaceholders() {
        #expect(SupabaseConfig.make(from: ["SupabaseURL": "<SET_ME>", "SupabaseAnonKey": "<SET_ME>"]) == nil)
        #expect(SupabaseConfig.make(from: ["SupabaseURL": "", "SupabaseAnonKey": "x"]) == nil)
        let ok = SupabaseConfig.make(from: ["SupabaseURL": "https://x.supabase.co", "SupabaseAnonKey": "anon123"])
        #expect(ok != nil)
        #expect(ok?.url.absoluteString == "https://x.supabase.co")
    }

    @Test func providerSelectsServiceByConfigState() {
        // `make` drives the choice: placeholders/invalid → unconfigured (mock),
        // valid → configured (live). This is bundle-independent so it holds
        // whether or not the shipped Supabase.plist has real values.
        #expect(SupabaseConfig.make(from: ["SupabaseURL": "<SET_ME>", "SupabaseAnonKey": "<SET_ME>"]) == nil)
        #expect(SupabaseConfig.make(from: [
            "SupabaseURL": "https://x.supabase.co", "SupabaseAnonKey": "anon",
        ]) != nil)
        // The live provider type matches whatever the bundled config resolves to.
        if SupabaseConfig.current == nil {
            #expect(MarketplaceServiceProvider.shared is MockMarketplaceService)
        } else {
            #expect(MarketplaceServiceProvider.shared is SupabaseMarketplaceService)
        }
    }

    // MARK: JWT subject extraction

    @Test func subjectExtractedFromJWT() {
        // header.payload.signature ; payload = {"sub":"user-123"}
        func b64url(_ s: String) -> String {
            Data(s.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let token = "\(b64url("{}")).\(b64url("{\"sub\":\"user-123\"}")).sig"
        #expect(SupabaseMarketplaceService.subject(fromJWT: token) == "user-123")
        #expect(SupabaseMarketplaceService.subject(fromJWT: "garbage") == nil)
    }
}
