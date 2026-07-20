import Foundation

// MARK: - RuffFormatTransform

#if os(macOS)
/// Formats Python code using the `ruff format` command.
/// If ruff is not installed or formatting fails, returns the input unchanged.
struct RuffFormatTransform: Transform {
    let id       = "ruff_format"
    let name     = "Format Python (Ruff)"
    let icon     = "chevron.left.forwardslash.chevron.right"
    let category = TransformCategory.code
    let applicableTo: [ContentType] = [.code]

    func apply(to input: String) -> String {
        guard let ruffPath = findRuff() else { return input }
        return runRuff(at: ruffPath, input: input) ?? input
    }

    // MARK: - Private

    private func findRuff() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ruff",
            "/usr/local/bin/ruff",
            "/usr/bin/ruff",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.local/bin/ruff",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.cargo/bin/ruff",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func runRuff(at path: String, input: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["format", "--stdin-filename", "input.py", "-"]

        let stdinPipe  = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput  = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain stdout/stderr concurrently BEFORE waiting: ruff's formatted
        // output easily exceeds the ~64KB pipe buffer, and if nobody reads it
        // ruff blocks on write while we block in waitUntilExit — a deadlock
        // that froze the calling main thread.
        var outputData = Data()
        let drain = DispatchGroup()
        drain.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        drain.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }

        if let data = input.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()
        drain.wait()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: outputData, encoding: .utf8)
    }
}
#endif
