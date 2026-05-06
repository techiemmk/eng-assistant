import Testing
import Foundation
import Core
@testable import Adapters

@Suite struct AVAudioPlaybackImplTests {
    @Test func emptyAudioReturnsImmediately() async throws {
        let playback = AVAudioPlaybackImpl()
        try await playback.play(SynthesizedAudio(data: Data(), sampleRate: 0))
    }

    @Test func instantiatesWithoutThrow() {
        _ = AVAudioPlaybackImpl()
    }
}
