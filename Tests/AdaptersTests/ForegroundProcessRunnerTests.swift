import Testing
import Foundation
@testable import Adapters

@Suite struct ForegroundProcessRunnerTests {
    @Test func runsEchoAndCapturesStdout() async throws {
        let runner = ForegroundProcessRunner()
        let result = try await runner.run(
            executable: "/bin/echo",
            arguments: ["hello", "world"],
            stdin: nil
        )
        #expect(result.exitCode == 0)
        let out = String(decoding: result.stdout, as: UTF8.self)
        #expect(out.contains("hello world"))
    }

    @Test func reportsNonZeroExitCode() async throws {
        let runner = ForegroundProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "exit 7"],
            stdin: nil
        )
        #expect(result.exitCode == 7)
    }

    @Test func passesStdinThrough() async throws {
        let runner = ForegroundProcessRunner()
        let result = try await runner.run(
            executable: "/bin/cat",
            arguments: [],
            stdin: Data("piped input".utf8)
        )
        #expect(result.exitCode == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "piped input")
    }

    @Test func missingExecutableThrows() async throws {
        let runner = ForegroundProcessRunner()
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(
                executable: "/usr/bin/this-does-not-exist-anywhere",
                arguments: [],
                stdin: nil
            )
        }
    }
}
