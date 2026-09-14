import Foundation

/// Runs a subprocess to completion. Drains stdout/stderr continuously via
/// readability handlers so the child can never block on a full pipe while the
/// parent is busy writing stdin. Writes stdin on a background queue, then
/// closes it. The termination handler resumes the continuation with the
/// fully-collected buffers.
public struct ForegroundProcessRunner: ProcessRunner {
    public init() {}

    public func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult {
        let url = URL(fileURLWithPath: executable)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if stdin != nil {
                process.standardInput = stdinPipe
            }

            // The stdout/stderr handlers and the termination handler all run
            // on different threads and all touch these buffers. They were
            // captured `var`s guarded by a separate lock, which is correct but
            // unprovable — the compiler sees a mutable capture in a concurrent
            // closure and can't tell the lock covers it. Holding them behind a
            // reference type that owns its own lock makes the safety checkable.
            let output = ProcessOutputBuffers()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                output.appendStandardOutput(chunk)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                output.appendStandardError(chunk)
            }

            process.terminationHandler = { proc in
                // Flush any remaining bytes the readability handler hasn't picked up.
                let outRest = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? nil
                let errRest = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let collected = output.drain(appendingStandardOutput: outRest,
                                             standardError: errRest)
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: collected.stdout,
                    stderr: collected.stderr
                ))
            }

            do {
                try process.run()
                if let stdin = stdin {
                    // Write stdin on a background queue so it can drain into the child
                    // while readability handlers concurrently drain stdout/stderr.
                    DispatchQueue.global(qos: .userInitiated).async {
                        let writer = stdinPipe.fileHandleForWriting
                        do {
                            try writer.write(contentsOf: stdin)
                        } catch {
                            // Child may have exited mid-write (broken pipe). The termination
                            // handler will report the exit code; we just ensure stdin closes.
                        }
                        try? writer.close()
                    }
                }
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed("\(error)"))
            }
        }
    }
}

/// Accumulates a subprocess's two output streams from whichever thread the
/// pipe handlers happen to run on.
///
/// `@unchecked Sendable` is load-bearing here rather than a shrug: every access
/// to the two buffers goes through `lock`, and they are `private` so there is no
/// way to reach them otherwise. That's the invariant the compiler can't verify
/// for itself.
private final class ProcessOutputBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func appendStandardOutput(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        stdout.append(chunk)
    }

    func appendStandardError(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        stderr.append(chunk)
    }

    /// Adds any final bytes and returns both buffers in one critical section,
    /// so the result can't straddle a concurrent append.
    func drain(
        appendingStandardOutput outRest: Data?,
        standardError errRest: Data?
    ) -> (stdout: Data, stderr: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let outRest { stdout.append(outRest) }
        if let errRest { stderr.append(errRest) }
        return (stdout, stderr)
    }
}
