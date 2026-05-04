import Foundation

public struct Voice: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct SynthesizedAudio: Equatable, Sendable {
    public let data: Data
    public let sampleRate: Int

    public init(data: Data, sampleRate: Int) {
        self.data = data
        self.sampleRate = sampleRate
    }
}

public protocol TTSProvider: Sendable {
    func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio
}
