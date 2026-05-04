import Foundation
import Core

public actor FakeTTSProvider: TTSProvider {
    public private(set) var synthesizedTexts: [String] = []

    public init() {}

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        synthesizedTexts.append(text)
        return SynthesizedAudio(data: Data(repeating: 0, count: 16), sampleRate: 16000)
    }
}
