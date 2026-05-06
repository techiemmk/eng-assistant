import Testing
import Foundation
import Core
import Fakes

/// In-memory persister for tests so we don't depend on Persistence.
final class InMemorySessionPersister: SessionPersisting, @unchecked Sendable {
    var sessions: [UUID: Session] = [:]
    func create(_ session: Session) throws { sessions[session.id] = session }
    func find(id: UUID) throws -> Session? { sessions[id] }
    func finalize(id: UUID, endedAt: Date, summary: String?) throws {
        guard var s = sessions[id] else { return }
        s.endedAt = endedAt; s.summary = summary; s.status = .ended
        sessions[id] = s
    }
    func listActive() throws -> [Session] {
        sessions.values.filter { $0.status == .active }
    }
}

final class InMemoryTurnPersister: TurnPersisting, @unchecked Sendable {
    var turns: [Turn] = []
    func append(_ turn: Turn) throws { turns.append(turn) }
    func list(forSession sessionId: UUID) throws -> [Turn] {
        turns.filter { $0.sessionId == sessionId }.sorted { $0.turnIndex < $1.turnIndex }
    }
    func markIncomplete(id: UUID) throws {
        if let i = turns.firstIndex(where: { $0.id == id }) { turns[i].isComplete = false }
    }
    func updateMetricsJson(turnId: UUID, json: String) throws {
        if let i = turns.firstIndex(where: { $0.id == turnId }) { turns[i].metricsJson = json }
    }
}

final class InMemoryAudioFilePersister: AudioFilePersisting, @unchecked Sendable {
    var written: [(sessionId: UUID, turnIndex: Int, speaker: Speaker, byteCount: Int)] = []
    func write(audio: Data, sessionId: UUID, turnIndex: Int, speaker: Speaker) throws -> String {
        written.append((sessionId, turnIndex, speaker, audio.count))
        return "audio/\(sessionId.uuidString)/\(speaker.rawValue)-turn-\(String(format: "%03d", turnIndex)).wav"
    }
}

@Suite struct SessionEngineTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.",
        openingLine: "Hi, how are you?",
        difficulty: 2, tags: [], notes: nil
    )

    private static func makeEngine(
        mode: SessionMode = .flow,
        scriptedReplies: [[String]] = [["I'm well, thanks!"]],
        scriptedTranscripts: [String] = [],
        scriptedClipByteCounts: [Int] = []
    ) -> (SessionEngine, InMemorySessionPersister, InMemoryTurnPersister, FakeAudioPlayback, FakeTTSProvider) {
        let sessionPersister = InMemorySessionPersister()
        let turnPersister = InMemoryTurnPersister()
        let llm = FakeLLMProvider(scriptedReplyBatches: scriptedReplies)
        let stt = FakeSTTProvider(scriptedTexts: scriptedTranscripts)
        let tts = FakeTTSProvider()
        let capture = FakeAudioCapture(scriptedClipByteCounts: scriptedClipByteCounts)
        let playback = FakeAudioPlayback()
        let engine = SessionEngine(
            scenario: scenario,
            mode: mode,
            activeWeakSpots: [],
            llm: llm,
            stt: stt,
            tts: tts,
            audioCapture: capture,
            audioPlayback: playback,
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            voice: Voice(id: "default", displayName: "Default"),
            llmOptions: LLMOptions(modelName: "fake")
        )
        return (engine, sessionPersister, turnPersister, playback, tts)
    }

    @Test func startCreatesSessionAndPlaysOpeningLineAndPersistsAITurn() async throws {
        let (engine, sessions, turns, playback, tts) = Self.makeEngine()
        try await engine.start()
        #expect(sessions.sessions.count == 1)
        let session = sessions.sessions.values.first!
        #expect(session.scenarioId == "test-01")
        #expect(session.status == .active)
        let allTurns = try turns.list(forSession: session.id)
        #expect(allTurns.count == 1)
        #expect(allTurns[0].speaker == .ai)
        #expect(allTurns[0].text == "Hi, how are you?")
        let played = await playback.playedClipSizes
        #expect(played.count == 1)
        let synthed = await tts.synthesizedTexts
        #expect(synthed == ["Hi, how are you?"])
    }

    @Test func runUserTurnPersistsBothUserAndAITurnsInOrder() async throws {
        let (engine, sessions, turns, _, _) = Self.makeEngine(
            scriptedReplies: [["I'm well, thanks!"]],
            scriptedTranscripts: ["I'm fine, how about you?"],
            scriptedClipByteCounts: [1000]
        )
        try await engine.start()
        _ = try await engine.runUserTurn()
        let session = sessions.sessions.values.first!
        let all = try turns.list(forSession: session.id)
        #expect(all.count == 3)  // ai-opening, user, ai-reply
        #expect(all[0].speaker == .ai)
        #expect(all[1].speaker == .user)
        #expect(all[1].text == "I'm fine, how about you?")
        #expect(all[2].speaker == .ai)
        #expect(all[2].text == "I'm well, thanks!")
        #expect(all.map(\.turnIndex) == [0, 1, 2])
    }

    @Test func coachModeReturnsCorrectionsAndStripsThemFromTTS() async throws {
        let scripted = [["I see! [[coach: try 'I think' instead of 'I am thinking']]"]]
        let (engine, _, turns, _, tts) = Self.makeEngine(
            mode: .coach,
            scriptedReplies: scripted,
            scriptedTranscripts: ["I am thinking that..."],
            scriptedClipByteCounts: [1000]
        )
        try await engine.start()
        let corrections = try await engine.runUserTurn()
        #expect(corrections == [Correction(message: "try 'I think' instead of 'I am thinking'")])
        let synthed = await tts.synthesizedTexts
        #expect(synthed.count == 2)
        #expect(synthed[1] == "I see! ")
        let session = (try await engine.sessionForTesting())!
        let all = try turns.list(forSession: session.id)
        let aiReply = all.last!
        #expect(aiReply.text.contains("[[coach:"))
    }

    @Test func endFinalizesSessionWithSummary() async throws {
        let (engine, sessions, _, _, _) = Self.makeEngine()
        try await engine.start()
        try await engine.end(summary: "Test session.")
        let session = sessions.sessions.values.first!
        #expect(session.status == .ended)
        #expect(session.summary == "Test session.")
        #expect(session.endedAt != nil)
    }

    @Test func llmFailureMarksUserTurnIncompleteAndKeepsHistoryClean() async throws {
        // Throwing fake LLM that fails on first call.
        struct ThrowingLLM: LLMProvider {
            func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error> {
                throw NSError(domain: "test", code: 1, userInfo: nil)
            }
        }
        let sessionPersister = InMemorySessionPersister()
        let turnPersister = InMemoryTurnPersister()
        let stt = FakeSTTProvider(scriptedTexts: ["hi there"])
        let tts = FakeTTSProvider()
        let capture = FakeAudioCapture(scriptedClipByteCounts: [100])
        let playback = FakeAudioPlayback()
        let engine = SessionEngine(
            scenario: Self.scenario,
            mode: .flow,
            activeWeakSpots: [],
            llm: ThrowingLLM(),
            stt: stt,
            tts: tts,
            audioCapture: capture,
            audioPlayback: playback,
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            voice: Voice(id: "v", displayName: "v"),
            llmOptions: LLMOptions(modelName: "fake")
        )
        try await engine.start()
        await #expect(throws: (any Error).self) {
            _ = try await engine.runUserTurn()
        }
        let sessionId = sessionPersister.sessions.values.first!.id
        let allTurns = try turnPersister.list(forSession: sessionId)
        // ai-opening + user (incomplete) — no AI reply turn
        #expect(allTurns.count == 2)
        let userTurn = allTurns[1]
        #expect(userTurn.speaker == .user)
        #expect(userTurn.isComplete == false)
    }

    @Test func systemPromptIncludesPersonaAndModeInstructions() async throws {
        let (engine, _, _, _, _) = Self.makeEngine(
            scriptedReplies: [["ok"]],
            scriptedTranscripts: ["hi"],
            scriptedClipByteCounts: [100]
        )
        try await engine.start()
        _ = try await engine.runUserTurn()
        let llm = await engine.llmForTesting() as! FakeLLMProvider
        let msgs = await llm.receivedMessages
        #expect(msgs.first?.role == .system)
        #expect(msgs.first?.content.contains("Test persona.") == true)
        #expect(msgs.contains { $0.role == .user && $0.content == "hi" })
    }

    @Test func audioFilePersisterIsCalledForEachTurnWhenProvided() async throws {
        let sessionPersister = InMemorySessionPersister()
        let turnPersister = InMemoryTurnPersister()
        let audioPersister = InMemoryAudioFilePersister()
        let llm = FakeLLMProvider(scriptedReplyBatches: [["Hello there."]])
        let stt = FakeSTTProvider(scriptedTexts: ["Hi."])
        let tts = FakeTTSProvider()
        let capture = FakeAudioCapture(scriptedClipByteCounts: [100])
        let playback = FakeAudioPlayback()
        let engine = SessionEngine(
            scenario: Self.scenario,
            mode: .flow,
            activeWeakSpots: [],
            llm: llm,
            stt: stt,
            tts: tts,
            audioCapture: capture,
            audioPlayback: playback,
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            voice: Voice(id: "v", displayName: "v"),
            llmOptions: LLMOptions(modelName: "fake"),
            audioFilePersister: audioPersister
        )
        try await engine.start()
        _ = try await engine.runUserTurn()
        // Three turns: AI opening, User, AI reply → all three should have written audio.
        #expect(audioPersister.written.count == 3)
        #expect(audioPersister.written.map(\.speaker) == [.ai, .user, .ai])
        #expect(audioPersister.written.map(\.turnIndex) == [0, 1, 2])
        let session = sessionPersister.sessions.values.first!
        let allTurns = try turnPersister.list(forSession: session.id)
        #expect(allTurns.allSatisfy { $0.audioPath != nil })
    }
}
