import Foundation
import Core

public actor FakeSTTProvider: STTProvider {
    private var scripted: [Transcript]
    public private(set) var receivedAudioByteCounts: [Int] = []

    public init(scriptedTranscripts: [Transcript]) {
        self.scripted = scriptedTranscripts
    }

    public init(scriptedTexts: [String], confidence: Double = 0.95) {
        self.scripted = scriptedTexts.map { Transcript(text: $0, confidence: confidence) }
    }

    public func transcribe(audio: Data) async throws -> Transcript {
        receivedAudioByteCounts.append(audio.count)
        guard !scripted.isEmpty else {
            throw FakeSTTProviderError.scriptExhausted
        }
        return scripted.removeFirst()
    }
}

public enum FakeSTTProviderError: Error, Equatable {
    case scriptExhausted
}
