import Foundation

public protocol AudioCapture: Sendable {
    /// Begin recording from the microphone. Returns immediately.
    func startRecording() async throws

    /// Stop recording and return the raw audio bytes. The format is
    /// implementation-defined; the matching `STTProvider` must accept it.
    func stopRecording() async throws -> Data

    /// True once the implementation's voice-activity detector has seen speech
    /// followed by a sustained silence, i.e. the speaker appears to be done.
    /// Callers poll this while recording to auto-stop a turn. Implementations
    /// without VAD keep the default (always false) and rely on the caller
    /// stopping explicitly.
    func hasEndpointed() async -> Bool
}

public extension AudioCapture {
    func hasEndpointed() async -> Bool { false }
}
