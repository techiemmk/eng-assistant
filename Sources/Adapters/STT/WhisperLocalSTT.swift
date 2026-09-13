import Foundation
import Core

public struct WhisperLocalSTT: STTProvider {
    /// Indirection over the two filesystem questions this adapter asks before
    /// launching whisper, so tests pairing a stub runner with made-up paths
    /// don't need those paths to exist.
    public struct FileProbe: Sendable {
        public var isExecutable: @Sendable (String) -> Bool
        public var isReadable: @Sendable (String) -> Bool

        public init(
            isExecutable: @escaping @Sendable (String) -> Bool,
            isReadable: @escaping @Sendable (String) -> Bool
        ) {
            self.isExecutable = isExecutable
            self.isReadable = isReadable
        }

        public static let fileSystem = FileProbe(
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
            isReadable: { FileManager.default.isReadableFile(atPath: $0) }
        )

        /// Accepts any path — for tests that stub the process runner.
        public static let alwaysPresent = FileProbe(isExecutable: { _ in true }, isReadable: { _ in true })
    }

    private let runner: ProcessRunner
    private let executablePath: String
    private let modelPath: String
    private let fileProbe: FileProbe

    public init(
        runner: ProcessRunner,
        executablePath: String,
        modelPath: String,
        fileProbe: FileProbe = .fileSystem
    ) {
        self.runner = runner
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.fileProbe = fileProbe
    }

    public func transcribe(audio: Data) async throws -> Transcript {
        // Check both paths up front: whisper-cli's own failure for a missing
        // model is an opaque non-zero exit, and the caller can act on these.
        guard fileProbe.isExecutable(executablePath) else {
            throw WhisperLocalSTTError.executableMissing(path: executablePath)
        }
        guard fileProbe.isReadable(modelPath) else {
            throw WhisperLocalSTTError.modelMissing(path: modelPath)
        }

        // whisper-cli reads a 16 kHz mono WAV from stdin with `--file -`.
        //
        // Getting the text back out is fussier than it looks. `--output-txt` is a
        // boolean, so the older `--output-txt -` spelling left the `-` to be
        // parsed as a second positional input file ("error: failed to read audio
        // file '-'"). And with stdin as the input, whisper derives its output
        // base name from the input name and stops printing segments to the
        // console — so without an explicit destination, stdout comes back empty.
        // `--output-txt --output-file -` names stdout as that destination.
        let args = [
            "--model", modelPath,
            "--file", "-",
            "--no-prints",
            "--no-timestamps",
            "--output-txt",
            "--output-file", "-",
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

public enum WhisperLocalSTTError: Error, Equatable, Sendable, LocalizedError {
    case transcriptionFailed(exitCode: Int32, stderr: String)
    case executableMissing(path: String)
    case modelMissing(path: String)

    public var errorDescription: String? {
        switch self {
        case .transcriptionFailed(let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "whisper-cli failed (exit \(exitCode))." + (detail.isEmpty ? "" : " \(detail)")
        case .executableMissing(let path):
            return "No whisper-cli executable at '\(path)'. Install it with `brew install whisper-cpp`, "
                + "then set the path in Settings > Speech-to-text."
        case .modelMissing(let path):
            return "No whisper model file at '\(path)'. Download a ggml model (e.g. ggml-base.en.bin) "
                + "and set its path in Settings > Speech-to-text."
        }
    }
}
