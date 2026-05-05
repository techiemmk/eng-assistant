import Foundation
import Core

public struct WhisperLocalSTT: STTProvider {
    private let runner: ProcessRunner
    private let executablePath: String
    private let modelPath: String

    public init(runner: ProcessRunner, executablePath: String, modelPath: String) {
        self.runner = runner
        self.executablePath = executablePath
        self.modelPath = modelPath
    }

    public func transcribe(audio: Data) async throws -> Transcript {
        // whisper-cli accepts WAV from stdin with --file -. Print plain text only
        // (--no-prints --no-timestamps) and write to stdout (--output-txt -).
        let args = [
            "--model", modelPath,
            "--file", "-",
            "--no-prints",
            "--no-timestamps",
            "--output-txt", "-",
        ]
        let result = try await runner.run(
            executable: executablePath,
            arguments: args,
            stdin: audio
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw WhisperLocalSTTError.transcriptionFailed(exitCode: result.exitCode, stderr: stderr)
        }
        let text = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // whisper.cpp doesn't surface a confidence value via the CLI, so we use
        // a coarse heuristic: empty output → 0; any output → 0.85 placeholder.
        let confidence = text.isEmpty ? 0.0 : 0.85
        return Transcript(text: text, confidence: confidence)
    }
}

public enum WhisperLocalSTTError: Error, Equatable, Sendable {
    case transcriptionFailed(exitCode: Int32, stderr: String)
}
