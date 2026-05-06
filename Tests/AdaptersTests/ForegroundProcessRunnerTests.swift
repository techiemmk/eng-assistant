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

    @Test func handlesLargeStdinWithoutDeadlock() async throws {
        let runner = ForegroundProcessRunner()
        // 256 KB of input — well past macOS's default ~64 KB pipe buffer.
        let big = Data(repeating: 0x41, count: 256 * 1024)
        let result = try await runner.run(
            executable: "/bin/cat",
            arguments: [],
            stdin: big
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == big.count)
    }
}
