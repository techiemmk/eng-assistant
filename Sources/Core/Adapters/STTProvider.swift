import Foundation

public struct Transcript: Equatable, Sendable {
    public var text: String
    public var confidence: Double  // 0..1

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol STTProvider: Sendable {
    func transcribe(audio: Data) async throws -> Transcript
}
