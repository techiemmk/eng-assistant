import Foundation

public protocol AudioCapture: Sendable {
    /// Begin recording from the microphone. Returns immediately.
    func startRecording() async throws

    /// Stop recording and return the raw audio bytes. The format is
    /// implementation-defined; the matching `STTProvider` must accept it.
    func stopRecording() async throws -> Data
}
