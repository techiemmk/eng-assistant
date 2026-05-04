import Foundation
import Core

public actor FakeAudioPlayback: AudioPlayback {
    public private(set) var playedClipSizes: [Int] = []

    public init() {}

    public func play(_ audio: SynthesizedAudio) async throws {
        playedClipSizes.append(audio.data.count)
    }
}
