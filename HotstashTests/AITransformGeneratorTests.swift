import Testing
@testable import Hotstash

/// A scripted `AIGenerationService` for the loop tests: hands back a fixed queue
/// of results and records every request it received so retry-feedback can be
/// asserted. The final response repeats if the loop asks for more.
private final class ScriptedAIService: AIGenerationService, @unchecked Sendable {
    private let responses: [Result<AIGeneratedTransform, AIGenerationError>]
    private var index = 0
    private(set) var requests: [AIGenerationRequest] = []

    init(_ responses: [Result<AIGeneratedTransform, AIGenerationError>]) {
        self.responses = responses
    }

    func generate(_ request: AIGenerationRequest, deviceID: String, entitlement: String) async throws -> AIGeneratedTransform {
        requests.append(request)
        let response = responses[min(index, responses.count - 1)]
        index += 1
        switch response {
        case .success(let transform): return transform
        case .failure(let error): throw error
        }
    }
}

private func makeTransform(js: String, name: String? = nil) -> AIGeneratedTransform {
    AIGeneratedTransform(js: js, name: name, description: nil, icon: nil, category: nil)
}

/// Transforms used across cases.
private let upperJS = makeTransform(js: "function transform(input){ return input.toUpperCase(); }")
private let identityJS = makeTransform(js: "function transform(input){ return input; }")
private let brokenJS = makeTransform(js: "function transform(input){ this is not valid js")

@MainActor
struct AITransformGeneratorTests {

    @Test("Verifies on the first attempt when output matches the example")
    func verifiesFirstAttempt() async throws {
        let service = ScriptedAIService([.success(upperJS)])
        let generator = AITransformGenerator(service: service)

        let outcome = try await generator.generate(
            description: "uppercase", exampleInput: "abc", expectedOutput: "ABC",
            deviceID: "device", entitlement: "jws"
        )

        #expect(outcome == .verified(upperJS))
        #expect(service.requests.count == 1)
    }

    @Test("Retries with feedback and verifies a later attempt")
    func verifiesAfterRetry() async throws {
        // First attempt returns input unchanged ("abc" != "ABC"); second is correct.
        let service = ScriptedAIService([.success(identityJS), .success(upperJS)])
        let generator = AITransformGenerator(service: service)

        let outcome = try await generator.generate(
            description: "uppercase", exampleInput: "abc", expectedOutput: "ABC",
            deviceID: "device", entitlement: "jws"
        )

        #expect(outcome == .verified(upperJS))
        #expect(service.requests.count == 2)
        // The retry must carry the previous JS and what it actually produced.
        #expect(service.requests[1].previousAttempt == identityJS.js)
        #expect(service.requests[1].actualOutput == "abc")
        #expect(service.requests[1].error == nil)
    }

    @Test("Feeds an error back when the generated script fails to run")
    func feedsBackScriptError() async throws {
        let service = ScriptedAIService([.success(brokenJS), .success(upperJS)])
        let generator = AITransformGenerator(service: service)

        let outcome = try await generator.generate(
            description: "uppercase", exampleInput: "abc", expectedOutput: "ABC",
            deviceID: "device", entitlement: "jws"
        )

        #expect(outcome == .verified(upperJS))
        #expect(service.requests[1].error == "script errored or timed out")
        #expect(service.requests[1].actualOutput == nil)
    }

    @Test("Returns the best attempt as unverified when nothing matches")
    func returnsUnverifiedWhenExhausted() async throws {
        let service = ScriptedAIService([.success(identityJS)])  // always wrong; repeats
        let generator = AITransformGenerator(service: service, maxAttempts: 3)

        let outcome = try await generator.generate(
            description: "uppercase", exampleInput: "abc", expectedOutput: "ABC",
            deviceID: "device", entitlement: "jws"
        )

        #expect(outcome == .unverified(identityJS))
        #expect(service.requests.count == 3)
    }

    @Test("Propagates service errors (not-Pro, rate-limited, etc.)")
    func propagatesServiceError() async {
        let service = ScriptedAIService([.failure(.rateLimited)])
        let generator = AITransformGenerator(service: service)

        await #expect(throws: AIGenerationError.rateLimited) {
            try await generator.generate(
                description: "x", exampleInput: "a", expectedOutput: "b",
                deviceID: "device", entitlement: "jws"
            )
        }
    }
}
