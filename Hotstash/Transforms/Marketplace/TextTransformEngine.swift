import Foundation
import JavaScriptCore

// MARK: - Result

/// The outcome of running an author-supplied text transform.
struct TextTransformResult: Equatable {
    let output: String
    let didError: Bool
}

// MARK: - Engine

/// Runs untrusted author JavaScript inside a locked-down `JSContext`.
///
/// Sandbox guarantees: a fresh context with no host objects bridged in (no network,
/// filesystem, or pasteboard access — only standard JS built-ins), a hard wall-clock
/// execution-time limit so infinite loops are terminated, and a cap on output byte size.
/// The engine never crashes and never force-unwraps; on any failure it returns the
/// original input unchanged with `didError == true`.
enum TextTransformEngine {
    /// Default thresholds for sandbox limits.
    private enum Limits {
        static let inputKey = "__hotstash_input" as NSString
        static let transformKey = "transform"
    }

    /// Run `js` against `input`, returning the transformed string or the original on failure.
    ///
    /// - Parameters:
    ///   - js: Author source. Expected to define a global `transform(input)` function.
    ///   - input: The text passed to `transform`.
    ///   - timeLimitMs: Hard wall-clock limit; longer-running scripts are terminated
    ///     (macOS) or abandoned on a watchdog thread (iOS — the JSC time-limit C API
    ///     is private there and App Store validation rejects it).
    ///   - maxOutputBytes: Maximum UTF-8 byte size of the returned string.
    static func run(
        js: String,
        input: String,
        timeLimitMs: Int = 250,
        maxOutputBytes: Int = 5_000_000
    ) -> TextTransformResult {
        #if os(macOS)
        return execute(js: js, input: input, timeLimitMs: timeLimitMs, maxOutputBytes: maxOutputBytes)
        #else
        return runWithWatchdog(js: js, input: input, timeLimitMs: timeLimitMs, maxOutputBytes: maxOutputBytes)
        #endif
    }

    #if !os(macOS)
    /// iOS path: execute on a dedicated thread and wait up to the limit (plus
    /// startup margin). On timeout the result is discarded and the thread is
    /// abandoned — JSC offers no public termination API on iOS, and marketplace
    /// scripts are server-moderated, so a runaway script is rare and bounded
    /// to one background thread rather than a hung UI.
    private static func runWithWatchdog(
        js: String,
        input: String,
        timeLimitMs: Int,
        maxOutputBytes: Int
    ) -> TextTransformResult {
        let failure = TextTransformResult(output: input, didError: true)

        final class ResultBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value: TextTransformResult?
            func set(_ result: TextTransformResult) { lock.lock(); value = result; lock.unlock() }
            func get() -> TextTransformResult? { lock.lock(); defer { lock.unlock() }; return value }
        }

        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        let thread = Thread {
            box.set(execute(js: js, input: input, timeLimitMs: timeLimitMs, maxOutputBytes: maxOutputBytes))
            semaphore.signal()
        }
        thread.qualityOfService = .userInitiated
        thread.start()

        // Generous margin over the nominal limit to absorb JSContext startup.
        let deadline = DispatchTime.now() + .milliseconds(max(timeLimitMs, 0) + 750)
        guard semaphore.wait(timeout: deadline) == .success else { return failure }
        return box.get() ?? failure
    }
    #endif

    /// Synchronous core shared by both platforms.
    private static func execute(
        js: String,
        input: String,
        timeLimitMs: Int,
        maxOutputBytes: Int
    ) -> TextTransformResult {
        let failure = TextTransformResult(output: input, didError: true)

        guard let context = JSContext() else {
            return failure
        }

        // Record whether the author code raised any exception.
        var didThrow = false
        context.exceptionHandler = { _, _ in
            didThrow = true
        }

        #if os(macOS)
        // Hard execution-time limit on the context's group. The callback returning `true`
        // terminates execution once the limit is exceeded, which protects against infinite
        // loops. This C API is private on iOS (App Store validation rejects the symbol),
        // so it is macOS-only; iOS relies on the watchdog in `runWithWatchdog`.
        if let globalRef = context.jsGlobalContextRef {
            let group = JSContextGetGroup(globalRef)
            let seconds = Double(max(timeLimitMs, 0)) / 1000.0
            JSContextGroupSetExecutionTimeLimit(group, seconds, { _, _ in true }, nil)
        }
        #endif

        // Provide the input as a global as a defensive fallback; we still prefer calling
        // `transform(input)` directly below.
        context.setObject(input, forKeyedSubscript: Limits.inputKey)

        // Define the author's `transform` function.
        context.evaluateScript(js)
        if didThrow {
            return failure
        }

        // Fetch and validate the `transform` function.
        guard let transformValue = context.objectForKeyedSubscript(Limits.transformKey),
              !transformValue.isUndefined,
              !transformValue.isNull else {
            return failure
        }

        // Invoke the function with the input.
        guard let resultValue = transformValue.call(withArguments: [input]) else {
            return failure
        }

        // Any thrown exception (including time-limit termination) sets the flag.
        if didThrow {
            return failure
        }

        // The result must be a JS string.
        guard resultValue.isString, let output = resultValue.toString() else {
            return failure
        }

        // Enforce the output byte cap.
        guard output.utf8.count <= maxOutputBytes else {
            return failure
        }

        return TextTransformResult(output: output, didError: false)
    }
}
