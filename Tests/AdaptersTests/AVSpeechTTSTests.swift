import Testing
import Foundation
import Core
@testable import Adapters

@Suite struct AVSpeechTTSTests {
    @Test func emptyTextReturnsEmptyAudio() async throws {
        let tts = AVSpeechTTS()
        let result = try await tts.synthesize(text: "", voice: Voice(id: "default", displayName: "Default"))
        #expect(result.data.isEmpty)
        #expect(result.sampleRate == 0)
    }

    // Real-audio synthesis is covered by LiveProvidersTests (gated on
    // RUN_LIVE_TESTS=1). The unit test deliberately avoids touching
    // AVSpeechSynthesizer.write because that API has been historically
    // inconsistent about end-of-stream signaling across macOS releases.
}
