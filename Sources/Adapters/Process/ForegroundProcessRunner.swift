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

            // Concurrent buffers protected by a lock — stdout/stderr handlers
            // and the termination handler all touch them.
            let lock = NSLock()
            var stdoutBuffer = Data()
            var stderrBuffer = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                lock.lock()
                stdoutBuffer.append(chunk)
                lock.unlock()
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                lock.lock()
                stderrBuffer.append(chunk)
                lock.unlock()
            }

            process.terminationHandler = { proc in
                // Flush any remaining bytes the readability handler hasn't picked up.
                let outRest = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? nil
                let errRest = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                lock.lock()
                if let r = outRest { stdoutBuffer.append(r) }
                if let r = errRest { stderrBuffer.append(r) }
                let out = stdoutBuffer
                let err = stderrBuffer
                lock.unlock()
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: out,
                    stderr: err
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
