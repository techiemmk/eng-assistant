import Foundation
import Core

public struct PiperTTS: TTSProvider {
    private let runner: ProcessRunner
    private let executablePath: String
    private let modelPath: String
    private let sampleRate: Int

    public init(
        runner: ProcessRunner,
        executablePath: String,
        modelPath: String,
        sampleRate: Int = 22050
    ) {
        self.runner = runner
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.sampleRate = sampleRate
    }

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        let args = [
            "--model", modelPath,
            "--output_file", "-",
        ]
        let result = try await runner.run(
            executable: executablePath,
            arguments: args,
            stdin: Data(text.utf8)
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw PiperTTSError.synthesisFailed(exitCode: result.exitCode, stderr: stderr)
        }
        return SynthesizedAudio(data: result.stdout, sampleRate: sampleRate)
    }
}

public enum PiperTTSError: Error, Equatable, Sendable {
    case synthesisFailed(exitCode: Int32, stderr: String)
}
