import Testing
@testable import Adapters

@Suite struct VADEndpointerTests {
    @Test func startsIdle() {
        let vad = VADEndpointer(speechThreshold: 0.1, silenceWindowMs: 1500)
        #expect(vad.state == .idle)
    }

    @Test func transitionsToSpeakingOnLoudFrame() {
        var vad = VADEndpointer(speechThreshold: 0.1, silenceWindowMs: 1500)
        vad.feed(rmsFrame: 0.5, durationMs: 20)
        #expect(vad.state == .speaking)
    }

    @Test func staysIdleOnQuietFrames() {
        var vad = VADEndpointer(speechThreshold: 0.1, silenceWindowMs: 1500)
        for _ in 0..<200 {
            vad.feed(rmsFrame: 0.05, durationMs: 20)
        }
        #expect(vad.state == .idle)
    }

    @Test func endpointsAfterSilenceWindowFollowingSpeech() {
        var vad = VADEndpointer(speechThreshold: 0.1, silenceWindowMs: 1500)
        for _ in 0..<10 {
            vad.feed(rmsFrame: 0.5, durationMs: 20)
        }
        #expect(vad.state == .speaking)
        for _ in 0..<75 {
            vad.feed(rmsFrame: 0.02, durationMs: 20)
        }
        #expect(vad.state == .endpointed)
    }

    @Test func intermittentSpeechResetsSilenceCounter() {
        var vad = VADEndpointer(speechThreshold: 0.1, silenceWindowMs: 1500)
        vad.feed(rmsFrame: 0.5, durationMs: 100)
        for _ in 0..<35 { vad.feed(rmsFrame: 0.02, durationMs: 20) }
        vad.feed(rmsFrame: 0.4, durationMs: 100)
        for _ in 0..<35 { vad.feed(rmsFrame: 0.02, durationMs: 20) }
        #expect(vad.state == .speaking)
    }
}
