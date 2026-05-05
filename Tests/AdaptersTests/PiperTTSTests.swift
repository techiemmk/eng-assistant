import Testing
import Foundation
import Core
@testable import Adapters

final class PiperStubProcessRunner: ProcessRunner, @unchecked Sendable {
    var nextResult: ProcessResult?
    var nextError: Error?
    var lastInvocation: (executable: String, arguments: [String], stdin: Data?)?

    func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult {
        lastInvocation = (executable, arguments, stdin)
        if let err = nextError { throw err }
        return nextResult ?? ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
}

@Suite struct PiperTTSTests {
    @Test func writesTextToStdinAndReturnsWavBytes() async throws {
        let runner = PiperStubProcessRunner()
        let fakeWav = Data(repeating: 0xAB, count: 1024)
        runner.nextResult = ProcessResult(exitCode: 0, stdout: fakeWav, stderr: Data())
        let tts = PiperTTS(
            runner: runner,
            executablePath: "/usr/local/bin/piper",
            modelPath: "/tmp/voice.onnx",
            sampleRate: 22050
        )
        let result = try await tts.synthesize(
            text: "Hello world.",
            voice: Voice(id: "amy", displayName: "Amy")
        )
        #expect(result.data == fakeWav)
        #expect(result.sampleRate == 22050)
        let stdin = String(decoding: runner.lastInvocation?.stdin ?? Data(), as: UTF8.self)
        #expect(stdin == "Hello world.")
        let args = runner.lastInvocation?.arguments ?? []
        #expect(args.contains("/tmp/voice.onnx"))
    }

    @Test func nonZeroExitCodeThrows() async throws {
        let runner = PiperStubProcessRunner()
        runner.nextResult = ProcessResult(
            exitCode: 2,
            stdout: Data(),
            stderr: Data("model file missing".utf8)
        )
        let tts = PiperTTS(
            runner: runner,
            executablePath: "/usr/local/bin/piper",
            modelPath: "/tmp/missing.onnx",
            sampleRate: 22050
        )
        await #expect(throws: PiperTTSError.self) {
            _ = try await tts.synthesize(text: "x", voice: Voice(id: "v", displayName: "V"))
        }
    }
}
