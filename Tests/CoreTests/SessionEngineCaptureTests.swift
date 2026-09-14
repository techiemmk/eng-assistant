import Testing
import Foundation
import Core
import Fakes

/// Covers the push-to-talk lifecycle. `runUserTurn()` used to open and close
/// the mic back-to-back, so the clip it transcribed was always empty; the
/// engine now hands that timing to the caller.
@Suite struct SessionEngineCaptureTests {
    private static let scenario = Scenario(
        id: "capture-01", source: .builtin, title: "Capture", domain: .corporate,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    private static func makeEngine(
        scriptedTranscripts: [String] = ["Hello there."],
        scriptedClipByteCounts: [Int] = [4096],
        endpointAfterPolls: Int? = nil
    ) -> (engine: SessionEngine, capture: FakeAudioCapture, turns: InMemoryTurnPersister) {
        let turnPersister = InMemoryTurnPersister()
        let capture = FakeAudioCapture(
            scriptedClipByteCounts: scriptedClipByteCounts,
            endpointAfterPolls: endpointAfterPolls
        )
        let engine = SessionEngine(
            scenario: scenario,
            mode: .flow,
            activeWeakSpots: [],
            llm: FakeLLMProvider(scriptedReplyBatches: [["Good to hear."]]),
            stt: FakeSTTProvider(scriptedTexts: scriptedTranscripts),
            tts: FakeTTSProvider(),
            audioCapture: capture,
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: InMemorySessionPersister(),
            turnPersister: turnPersister,
            voice: Voice(id: "default", displayName: "Default"),
            llmOptions: LLMOptions(modelName: "fake")
        )
        return (engine, capture, turnPersister)
    }

    @Test func beginUserSpeechOpensMicAndLeavesItOpen() async throws {
        let (engine, capture, _) = Self.makeEngine()
        try await engine.start()
        try await engine.beginUserSpeech()

        #expect(await engine.isCapturingSpeech())
        #expect(await capture.startCount == 1)
        // The mic is still open — nothing has been read off it yet.
        #expect(await capture.stopCount == 0)
    }

    @Test func finishUserSpeechClosesMicAndRunsTheTurn() async throws {
        let (engine, capture, turns) = Self.makeEngine()
        try await engine.start()
        try await engine.beginUserSpeech()
        _ = try await engine.finishUserSpeech()

        #expect(await engine.isCapturingSpeech() == false)
        #expect(await capture.stopCount == 1)
        let texts = turns.turns.map(\.text)
        #expect(texts == ["Hi.", "Hello there.", "Good to hear."])
    }

    @Test func beginTwiceThrows() async throws {
        let (engine, _, _) = Self.makeEngine()
        try await engine.start()
        try await engine.beginUserSpeech()
        await #expect(throws: SessionEngineError.alreadyCapturing) {
            try await engine.beginUserSpeech()
        }
    }

    @Test func finishWithoutBeginThrows() async throws {
        let (engine, _, _) = Self.makeEngine()
        try await engine.start()
        await #expect(throws: SessionEngineError.notCapturing) {
            _ = try await engine.finishUserSpeech()
        }
    }

    /// A 16-bit mono WAV with no samples is 44 bytes of header. Sending that to
    /// the transcriber is pointless, and persisting a turn for it pollutes the
    /// debrief, so the engine refuses before either happens.
    @Test func emptyClipThrowsWithoutPersistingATurn() async throws {
        let (engine, _, turns) = Self.makeEngine(scriptedClipByteCounts: [44])
        try await engine.start()
        try await engine.beginUserSpeech()
        await #expect(throws: SessionEngineError.noSpeechCaptured) {
            _ = try await engine.finishUserSpeech()
        }
        // Only the opening AI line — no empty user turn.
        #expect(turns.turns.count == 1)
        #expect(await engine.isCapturingSpeech() == false)
    }

    @Test func blankTranscriptThrowsWithoutPersistingATurn() async throws {
        let (engine, _, turns) = Self.makeEngine(scriptedTranscripts: ["   \n "])
        try await engine.start()
        try await engine.beginUserSpeech()
        await #expect(throws: SessionEngineError.noSpeechCaptured) {
            _ = try await engine.finishUserSpeech()
        }
        #expect(turns.turns.count == 1)
    }

    @Test func captureHasEndpointedReportsTheDevicesVAD() async throws {
        let (engine, _, _) = Self.makeEngine(endpointAfterPolls: 2)
        try await engine.start()

        // Not capturing yet — never consult the device.
        #expect(await engine.captureHasEndpointed() == false)

        try await engine.beginUserSpeech()
        #expect(await engine.captureHasEndpointed() == false)  // poll 1
        #expect(await engine.captureHasEndpointed() == true)   // poll 2
    }

    @Test func cancelUserSpeechClosesMicWithoutRunningATurn() async throws {
        let (engine, capture, turns) = Self.makeEngine()
        try await engine.start()
        try await engine.beginUserSpeech()
        await engine.cancelUserSpeech()

        #expect(await engine.isCapturingSpeech() == false)
        #expect(await capture.stopCount == 1)
        #expect(turns.turns.count == 1)
    }

    @Test func endClosesAnOpenMic() async throws {
        let (engine, capture, _) = Self.makeEngine()
        try await engine.start()
        try await engine.beginUserSpeech()
        try await engine.end(summary: nil)

        #expect(await engine.isCapturingSpeech() == false)
        #expect(await capture.stopCount == 1)
    }

    @Test func runUserTurnStillWorksAsAOneShot() async throws {
        let (engine, capture, turns) = Self.makeEngine()
        try await engine.start()
        _ = try await engine.runUserTurn()

        #expect(await capture.startCount == 1)
        #expect(await capture.stopCount == 1)
        #expect(turns.turns.count == 3)
    }
}
