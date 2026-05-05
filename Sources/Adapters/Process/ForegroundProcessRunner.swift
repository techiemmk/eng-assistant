import Foundation

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

            process.terminationHandler = { proc in
                let out = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: out ?? Data(),
                    stderr: err ?? Data()
                ))
            }

            do {
                try process.run()
                if let stdin = stdin {
                    let writer = stdinPipe.fileHandleForWriting
                    try writer.write(contentsOf: stdin)
                    try writer.close()
                }
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed("\(error)"))
            }
        }
    }
}
