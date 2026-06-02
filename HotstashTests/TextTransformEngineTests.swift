import Testing
@testable import Hotstash

struct TextTransformEngineTests {
    // A low time limit keeps timeout-based tests fast.
    private let fastLimitMs = 150

    @Test("Correct transform uppercases input")
    func correctTransform() {
        let js = "function transform(input){ return input.toUpperCase(); }"
        let result = TextTransformEngine.run(js: js, input: "abc", timeLimitMs: fastLimitMs)
        #expect(result.output == "ABC")
        #expect(result.didError == false)
    }

    @Test("Multiline logic trims, filters, and joins lines")
    func multilineLogic() {
        let js = """
        function transform(input){
            return input
                .split("\\n")
                .map(function(line){ return line.trim(); })
                .filter(function(line){ return line.length > 0; })
                .join(", ");
        }
        """
        let input = "  alpha \n\n beta  \n   \ngamma"
        let result = TextTransformEngine.run(js: js, input: input, timeLimitMs: fastLimitMs)
        #expect(result.output == "alpha, beta, gamma")
        #expect(result.didError == false)
    }

    @Test("Infinite loop is terminated by the time limit")
    func infiniteLoopTerminated() {
        let js = "function transform(input){ while(true){} }"
        let result = TextTransformEngine.run(js: js, input: "keep-me", timeLimitMs: fastLimitMs)
        #expect(result.didError == true)
        #expect(result.output == "keep-me")
    }

    @Test("Syntax error returns the input unchanged")
    func syntaxError() {
        let js = "function transform(input){ return "
        let result = TextTransformEngine.run(js: js, input: "stay", timeLimitMs: fastLimitMs)
        #expect(result.didError == true)
        #expect(result.output == "stay")
    }

    @Test("Non-string return is treated as an error")
    func nonStringReturn() {
        let js = "function transform(input){ return 42; }"
        let result = TextTransformEngine.run(js: js, input: "stay", timeLimitMs: fastLimitMs)
        #expect(result.didError == true)
        #expect(result.output == "stay")
    }

    @Test("Missing transform function is an error")
    func missingFunction() {
        let js = "var x = 1;"
        let result = TextTransformEngine.run(js: js, input: "stay", timeLimitMs: fastLimitMs)
        #expect(result.didError == true)
        #expect(result.output == "stay")
    }

    @Test("Exception thrown inside transform is an error")
    func throwsInside() {
        let js = "function transform(input){ throw new Error('x'); }"
        let result = TextTransformEngine.run(js: js, input: "stay", timeLimitMs: fastLimitMs)
        #expect(result.didError == true)
        #expect(result.output == "stay")
    }

    @Test("Output exceeding the byte cap is rejected")
    func outputCapExceeded() {
        // A huge repeat either exceeds the cap or is killed by the time limit; either way
        // the result is an error and the input is preserved.
        let js = "function transform(input){ return input.repeat(10000000); }"
        let result = TextTransformEngine.run(
            js: js,
            input: "stay",
            timeLimitMs: fastLimitMs,
            maxOutputBytes: 1000
        )
        #expect(result.didError == true)
        #expect(result.output == "stay")
    }

    @Test("No networking globals are bridged into the sandbox")
    func noNetworkGlobals() {
        let js = "function transform(input){ return typeof fetch + ',' + typeof XMLHttpRequest; }"
        let result = TextTransformEngine.run(js: js, input: "", timeLimitMs: fastLimitMs)
        #expect(result.output == "undefined,undefined")
        #expect(result.didError == false)
    }
}
