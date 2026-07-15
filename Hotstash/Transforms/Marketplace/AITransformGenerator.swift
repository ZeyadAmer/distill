import Foundation

/// Orchestrates AI transform generation with a self-correcting loop.
///
/// Each attempt asks the service for JS, then runs it locally against the user's
/// example via `TextTransformEngine` (the same isolated JSContext all transforms
/// use — no second execution path). If the output matches the expected output,
/// that version wins. Otherwise the mismatch (or error) is fed back into the next
/// request so the model can correct itself, up to `maxAttempts` times.
///
/// Verification is exact string equality against the example — the example is
/// authoritative. If no attempt verifies, the best (last) attempt is returned as
/// `.unverified` so the editor is still filled for manual fixing.
@MainActor
final class AITransformGenerator {

    enum Outcome: Equatable {
        /// Ran locally and matched the expected output.
        case verified(AIGeneratedTransform)
        /// Never matched; this is the last attempt, editor still gets filled.
        case unverified(AIGeneratedTransform)
    }

    private let service: AIGenerationService
    private let maxAttempts: Int

    init(service: AIGenerationService, maxAttempts: Int = 3) {
        self.service = service
        self.maxAttempts = max(1, maxAttempts)
    }

    /// Generate and self-verify. Throws only when generation itself fails (network,
    /// not-Pro, rate-limited, decode). A generated-but-wrong result returns
    /// `.unverified` rather than throwing.
    func generate(
        description: String,
        exampleInput: String,
        expectedOutput: String,
        deviceID: String,
        entitlement: String
    ) async throws -> Outcome {
        var previousJs: String?
        var lastActualOutput: String?
        var lastError: String?
        var best: AIGeneratedTransform?

        for _ in 1...maxAttempts {
            let request = AIGenerationRequest(
                description: description,
                exampleInput: exampleInput,
                expectedOutput: expectedOutput,
                previousAttempt: previousJs,
                actualOutput: lastActualOutput,
                error: lastError
            )
            let candidate = try await service.generate(request, deviceID: deviceID, entitlement: entitlement)
            best = candidate

            let run = TextTransformEngine.run(js: candidate.js, input: exampleInput)
            if !run.didError && run.output == expectedOutput {
                return .verified(candidate)
            }

            // Feed the discrepancy back for the next attempt.
            previousJs = candidate.js
            lastActualOutput = run.didError ? nil : run.output
            lastError = run.didError ? "script errored or timed out" : nil
        }

        // Exhausted attempts without a match — return the best we produced.
        // `best` is always non-nil here: the loop runs at least once and any
        // service failure would have thrown before reaching this point.
        guard let best else { throw AIGenerationError.decoding }
        return .unverified(best)
    }
}
