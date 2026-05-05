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
            modelPath: "/tmp/whisper-small.en.bin"
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
            modelPath: "/tmp/m.bin"
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
            modelPath: "/tmp/missing.bin"
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
            modelPath: "/tmp/m.bin"
        )
        let transcript = try await stt.transcribe(audio: Data(repeating: 0, count: 16))
        #expect(transcript.text == "")
        #expect(transcript.confidence == 0)
    }
}
