import Testing
import Foundation
import Core
@testable import Adapters

@Suite struct AVAudioCaptureImplTests {
    @Test func instantiatesWithoutThrow() {
        let capture = AVAudioCaptureImpl(
            sampleRate: 16000,
            vad: VADEndpointer(speechThreshold: 0.05, silenceWindowMs: 1500)
        )
        _ = capture
    }
}
