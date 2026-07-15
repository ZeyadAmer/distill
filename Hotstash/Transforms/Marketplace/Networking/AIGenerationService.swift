import Foundation

// MARK: - Request / Response

/// What the user gives us: a description and one worked example. On a retry we
/// also send the previous JS and what it actually produced so the model can fix
/// the discrepancy.
struct AIGenerationRequest: Equatable {
    let description: String
    let exampleInput: String
    let expectedOutput: String
    let previousAttempt: String?
    let actualOutput: String?
    let error: String?

    init(
        description: String,
        exampleInput: String,
        expectedOutput: String,
        previousAttempt: String? = nil,
        actualOutput: String? = nil,
        error: String? = nil
    ) {
        self.description = description
        self.exampleInput = exampleInput
        self.expectedOutput = expectedOutput
        self.previousAttempt = previousAttempt
        self.actualOutput = actualOutput
        self.error = error
    }
}

/// A generated transform: the executable JS plus optional metadata suggestions.
/// Only `js` is required; the rest pre-fill authoring fields the user can edit.
struct AIGeneratedTransform: Equatable, Decodable {
    let js: String
    let name: String?
    let description: String?
    let icon: String?
    let category: String?
}

// MARK: - Errors

/// Failure modes surfaced to the authoring UI. All are recoverable — the editor
/// stays usable for manual authoring no matter which fires.
enum AIGenerationError: LocalizedError, Equatable {
    case notPro
    case rateLimited
    case notConfigured
    case network
    case decoding
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notPro:        return "AI generation is a Pro feature. Upgrade to use it."
        case .rateLimited:   return "Daily generation limit reached. Try again tomorrow."
        case .notConfigured: return "AI generation isn't available in this build."
        case .network:       return "Couldn't reach the server. Check your connection."
        case .decoding:      return "The server returned an unexpected response."
        case .server(let m): return m
        }
    }
}

// MARK: - Service protocol

/// Abstraction over the AI generation backend, mirroring `MarketplaceService`:
/// the app talks only to this protocol so the live Supabase Edge Function and the
/// offline mock are interchangeable.
protocol AIGenerationService {
    /// Generate one JS transform for the request. `deviceID` is the anonymous
    /// per-install id (rate limiting); `entitlement` is the Pro StoreKit proof.
    func generate(_ request: AIGenerationRequest, deviceID: String, entitlement: String) async throws -> AIGeneratedTransform
}

// MARK: - Live implementation

/// Live backend over the Supabase `generate-transform` Edge Function. The Gemini
/// key lives server-side; this only forwards the request plus the anonymous
/// device id and the Pro entitlement proof.
struct SupabaseAIGenerationService: AIGenerationService {

    let config: SupabaseConfig
    private let session: URLSession

    init(config: SupabaseConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func generate(_ request: AIGenerationRequest, deviceID: String, entitlement: String) async throws -> AIGeneratedTransform {
        guard let url = URL(string: config.url.absoluteString + "/functions/v1/generate-transform") else {
            throw AIGenerationError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(deviceID, forHTTPHeaderField: "X-Hotstash-Device")
        req.setValue(entitlement, forHTTPHeaderField: "X-Hotstash-Entitlement")

        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "description": request.description,
            "exampleInput": request.exampleInput,
            "expectedOutput": request.expectedOutput,
            "previousAttempt": request.previousAttempt as Any,
            "actualOutput": request.actualOutput as Any,
            "error": request.error as Any,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AIGenerationError.network
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch code {
        case 200..<300: break
        case 403: throw AIGenerationError.notPro
        case 429: throw AIGenerationError.rateLimited
        default:
            let text = String(data: data, encoding: .utf8) ?? ""
            let reason = SupabaseMarketplaceService.extractReason(text) ?? "Generation failed (HTTP \(code))."
            throw AIGenerationError.server(reason)
        }

        guard let result = try? JSONDecoder().decode(AIGeneratedTransform.self, from: data),
              !result.js.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIGenerationError.decoding
        }
        return result
    }
}

// MARK: - Provider

/// Resolves the AI generation backend: the live Supabase service when configured,
/// otherwise nil (the feature is hidden when there's no backend). Mirrors
/// `MarketplaceServiceProvider`.
enum AIGenerationServiceProvider {
    static var shared: AIGenerationService? {
        guard let config = SupabaseConfig.current else { return nil }
        return SupabaseAIGenerationService(config: config)
    }

    static var isConfigured: Bool { SupabaseConfig.current != nil }
}
