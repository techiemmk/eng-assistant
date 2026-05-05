import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case executableNotFound(String)
    case launchFailed(String)
}
