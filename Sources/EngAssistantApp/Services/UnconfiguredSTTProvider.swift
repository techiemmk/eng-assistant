import Foundation
import Core

/// Stands in for a real `STTProvider` until whisper.cpp is set up. It fails
/// loudly rather than returning placeholder text: a fake transcript makes the
/// app *look* like it works while the AI answers words the user never said.
public struct UnconfiguredSTTProvider: STTProvider {
    public init() {}

    public func transcribe(audio: Data) async throws -> Transcript {
        throw UnconfiguredSTTError.notConfigured
    }
}

public enum UnconfiguredSTTError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        "Speech-to-text isn't set up yet, so the app can't hear you. Install whisper.cpp "
            + "(`brew install whisper-cpp`), put a ggml model in "
            + "~/Library/Application Support/EngAssistant/models/, then check "
            + "Settings > Speech-to-text."
    }
}
