import Foundation
import Persistence

/// Finds a whisper.cpp install without asking the user to type paths. Checks
/// the usual Homebrew locations for the binary, and the app's own models
/// directory for a ggml model file.
public struct STTLocator: Sendable {
    /// Where whisper.cpp lands via Homebrew on Apple Silicon and Intel. The
    /// formula is `whisper-cpp`; the binary has been named both `whisper-cli`
    /// (current) and `whisper-cpp` (older), so both are probed.
    public static let candidateExecutables = [
        "/opt/homebrew/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cli",
        "/usr/local/bin/whisper-cpp",
    ]

    private let modelsDirectory: URL
    private let executableCandidates: [String]

    public init(
        modelsDirectory: URL = StorageLayout().modelsDirectory,
        executableCandidates: [String] = STTLocator.candidateExecutables
    ) {
        self.modelsDirectory = modelsDirectory
        self.executableCandidates = executableCandidates
    }

    public func findExecutable() -> String? {
        executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Picks the largest `.bin` in the models directory — with several models
    /// present the biggest is the most accurate, and size is the only signal
    /// available without parsing the file.
    public func findModel() -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return nil }

        return entries
            .filter { $0.pathExtension.lowercased() == "bin" }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return (url: url, size: size)
            }
            .max { $0.size < $1.size }?
            .url.path
    }
}
