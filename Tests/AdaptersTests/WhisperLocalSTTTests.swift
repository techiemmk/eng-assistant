import Testing
import Foundation
import Core
@testable import Adapters

final class StubProcessRunner: ProcessRunner, @unchecked Sendable {
    var nextResult: ProcessResult?
    var nextError: Error?
    var lastInvocation: (executable: String, arguments: [String], stdin: Data?)?

    func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult {
        lastInvocation = (executable, arguments, stdin)
        if let err = nextError { throw err }
        return nextResult ?? ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
}

@Suite struct WhisperLocalSTTTests {
    @Test func returnsTranscriptFromStdout() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(
            exitCode: 0,
            stdout: Data("Yesterday I finished the auth refactor.\n".utf8),
            stderr: Data()
        )
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/whisper-small.en.bin",
            fileProbe: .alwaysPresent
        )
        let transcript = try await stt.transcribe(audio: Data(repeating: 0, count: 16))
        #expect(transcript.text == "Yesterday I finished the auth refactor.")
        #expect(transcript.confidence > 0)
    }

    @Test func passesAudioBytesAsStdin() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(exitCode: 0, stdout: Data("ok".utf8), stderr: Data())
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/m.bin",
            fileProbe: .alwaysPresent
        )
        let audio = Data([1, 2, 3, 4, 5])
        _ = try await stt.transcribe(audio: audio)
        #expect(runner.lastInvocation?.stdin == audio)
        #expect(runner.lastInvocation?.executable == "/usr/local/bin/whisper-cli")
        let args = runner.lastInvocation?.arguments ?? []
        #expect(args.contains("/tmp/m.bin"))
    }

    @Test func nonZeroExitCodeThrows() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(
            exitCode: 1,
            stdout: Data(),
            stderr: Data("model not found".utf8)
        )
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/missing.bin",
            fileProbe: .alwaysPresent
        )
        await #expect(throws: WhisperLocalSTTError.self) {
            _ = try await stt.transcribe(audio: Data())
        }
    }

    @Test func emptyStdoutReturnsLowConfidenceTranscript() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/m.bin",
            fileProbe: .alwaysPresent
        )
        let transcript = try await stt.transcribe(audio: Data(repeating: 0, count: 16))
        #expect(transcript.text == "")
        #expect(transcript.confidence == 0)
    }
}

/// The argument list is load-bearing and was wrong against real whisper-cli
/// 1.9.4: `--output-txt` is a boolean, so `--output-txt -` left the `-` to be
/// read as a second input file, and with stdin as the input whisper prints
/// nothing to the console unless an output destination is named.
@Suite struct WhisperLocalSTTArgumentTests {
    private static func invoke() async throws -> [String] {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(exitCode: 0, stdout: Data("hi".utf8), stderr: Data())
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/opt/homebrew/bin/whisper-cli",
            modelPath: "/models/ggml-base.en.bin",
            fileProbe: .alwaysPresent
        )
        _ = try await stt.transcribe(audio: Data(repeating: 1, count: 64))
        return runner.lastInvocation?.arguments ?? []
    }

    @Test func namesStdoutAsTheOutputDestination() async throws {
        let args = try await Self.invoke()
        let outputTxt = try #require(args.firstIndex(of: "--output-txt"))
        let outputFile = try #require(args.firstIndex(of: "--output-file"))
        // --output-txt takes no value; the destination rides on --output-file.
        #expect(args[outputTxt + 1] == "--output-file")
        #expect(args[outputFile + 1] == "-")
    }

    /// Every "-" must be the value of a flag that takes one. A bare "-" sitting
    /// after a boolean flag is what whisper reads as a second input file.
    @Test func hasNoStrayDashPositional() async throws {
        let args = try await Self.invoke()
        let flagsTakingAValue: Set<String> = ["--file", "--output-file", "--model"]
        for (index, arg) in args.enumerated() where arg == "-" {
            let preceding = index > 0 ? args[index - 1] : ""
            #expect(
                flagsTakingAValue.contains(preceding),
                "bare \"-\" at index \(index) follows \(preceding), which takes no value"
            )
        }
        let file = try #require(args.firstIndex(of: "--file"))
        #expect(args[file + 1] == "-")
    }

    @Test func readsTheModelAndSuppressesChatter() async throws {
        let args = try await Self.invoke()
        let model = try #require(args.firstIndex(of: "--model"))
        #expect(args[model + 1] == "/models/ggml-base.en.bin")
        #expect(args.contains("--no-prints"))
        #expect(args.contains("--no-timestamps"))
    }
}
