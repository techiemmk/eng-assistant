import Testing
import Foundation
import Core
import Fakes

/// Resuming has to give the model the earlier conversation back as context,
/// without replaying the greeting or re-numbering the turns.
@Suite struct SessionResumeTests {
    private static let scenario = Scenario(
        id: "resume-01", source: .builtin, title: "Resume", domain: .workplace,
        persona: "Test persona.", openingLine: "Morning.",
        difficulty: 2, tags: [], notes: nil
    )

    private static func makeEngine(
        sessions: InMemorySessionPersister,
        turns: InMemoryTurnPersister,
        scriptedReplies: [[String]] = [["Carrying on."]],
        scriptedTranscripts: [String] = ["And another thing."],
        clipByteCounts: [Int] = [4096],
        llm: FakeLLMProvider? = nil
    ) -> (SessionEngine, FakeLLMProvider) {
        let provider = llm ?? FakeLLMProvider(scriptedReplyBatches: scriptedReplies)
        let engine = SessionEngine(
            scenario: scenario,
            mode: .flow,
            activeWeakSpots: [],
            llm: provider,
            stt: FakeSTTProvider(scriptedTexts: scriptedTranscripts),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: clipByteCounts),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: sessions,
            turnPersister: turns,
            voice: Voice(id: "default", displayName: "Default"),
            llmOptions: LLMOptions(modelName: "fake")
        )
        return (engine, provider)
    }

    /// Builds a session that already holds: opening line, one user turn, one AI
    /// reply — i.e. what an ended session looks like on disk.
    private static func seedEndedSession(
        sessions: InMemorySessionPersister,
        turns: InMemoryTurnPersister
    ) -> UUID {
        let id = UUID()
        try! sessions.create(Session(
            id: id, scenarioId: scenario.id, startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2000), mode: .flow, status: .ended,
            summary: "earlier", personaSnapshot: scenario.persona
        ))
        let texts: [(Speaker, String)] = [
            (.ai, "Morning."),
            (.user, "I finished the deploy yesterday."),
            (.ai, "Good — any fallout?"),
        ]
        for (index, entry) in texts.enumerated() {
            try! turns.append(Turn(
                id: UUID(), sessionId: id, turnIndex: index, speaker: entry.0,
                text: entry.1, audioPath: nil, startedAt: Date(), durationMs: 0,
                metricsJson: nil, isComplete: true
            ))
        }
        return id
    }

    @Test func resumeReopensAnEndedSession() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        let (engine, _) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)

        #expect(sessions.sessions[id]?.status == .active)
        #expect(sessions.sessions[id]?.endedAt == nil)
    }

    /// A fresh start() speaks the opening line; resuming must not, because the
    /// user already heard it.
    @Test func resumeDoesNotReplayTheOpeningLine() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        let tts = FakeTTSProvider()
        let engine = SessionEngine(
            scenario: Self.scenario, mode: .flow, activeWeakSpots: [],
            llm: FakeLLMProvider(scriptedReplies: ["ok"]),
            stt: FakeSTTProvider(scriptedTexts: []), tts: tts,
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: []),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: sessions, turnPersister: turns,
            voice: Voice(id: "default", displayName: "Default"),
            llmOptions: LLMOptions(modelName: "fake")
        )

        try await engine.resume(sessionId: id)

        #expect(await tts.synthesizedTexts.isEmpty)
        #expect(turns.turns.count == 3, "resuming must not append a turn")
    }

    /// The whole point: the next reply has to be generated with the earlier
    /// conversation in the prompt.
    @Test func resumedHistoryIsSentToTheModel() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        let (engine, llm) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)
        _ = try await engine.runUserTurn()

        let sent = await llm.receivedMessages
        let contents = sent.map(\.content)
        #expect(contents.contains("I finished the deploy yesterday."))
        #expect(contents.contains("Good — any fallout?"))
        #expect(contents.contains("And another thing."))
        // The greeting wasn't authored by the model, so it stays out of history.
        #expect(!contents.contains("Morning."))
    }

    @Test func resumedHistoryKeepsSpeakerRoles() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        let (engine, llm) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)
        _ = try await engine.runUserTurn()

        let sent = await llm.receivedMessages
        #expect(sent.first?.role == .system)
        let replayed = sent.dropFirst().prefix(2)
        #expect(replayed.map(\.role) == [.user, .assistant])
    }

    /// New turns must continue the numbering, not overwrite turn 0.
    @Test func newTurnsContinueTheExistingNumbering() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        let (engine, _) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)
        _ = try await engine.runUserTurn()

        let all = try turns.list(forSession: id)
        #expect(all.map(\.turnIndex) == [0, 1, 2, 3, 4])
        #expect(all[3].speaker == .user)
        #expect(all[4].speaker == .ai)
    }

    /// An incomplete turn is the user half of a turn whose reply failed;
    /// replaying it would leave a dangling user message with no answer.
    @Test func incompleteTurnsAreLeftOutOfTheReplayedHistory() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        try turns.append(Turn(
            id: UUID(), sessionId: id, turnIndex: 3, speaker: .user,
            text: "This one never got a reply.", audioPath: nil,
            startedAt: Date(), durationMs: 0, metricsJson: nil, isComplete: false
        ))
        let (engine, llm) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)
        _ = try await engine.runUserTurn()

        let contents = await llm.receivedMessages.map(\.content)
        #expect(!contents.contains("This one never got a reply."))
    }

    @Test func resumeRejectsAnUnknownSession() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let (engine, _) = Self.makeEngine(sessions: sessions, turns: turns)
        let missing = UUID()
        await #expect(throws: SessionEngineError.sessionNotFound(missing)) {
            try await engine.resume(sessionId: missing)
        }
    }

    /// The engine carries one scenario's persona; resuming another scenario's
    /// session into it would silently swap the character mid-conversation.
    @Test func resumeRejectsAnotherScenariosSession() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = UUID()
        try sessions.create(Session(
            id: id, scenarioId: "some-other-scenario", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "Other"
        ))
        let (engine, _) = Self.makeEngine(sessions: sessions, turns: turns)

        await #expect(throws: SessionEngineError.scenarioMismatch(
            expected: "resume-01", found: "some-other-scenario"
        )) {
            try await engine.resume(sessionId: id)
        }
    }

    /// A session that crashed mid-conversation is still `.active`; resuming it
    /// shouldn't need a status change.
    @Test func resumeWorksOnAnAlreadyActiveSession() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = UUID()
        try sessions.create(Session(
            id: id, scenarioId: Self.scenario.id, startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: Self.scenario.persona
        ))
        let (engine, _) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)
        #expect(sessions.sessions[id]?.status == .active)
        #expect(try await engine.storedTurns().isEmpty)
    }

    @Test func storedTurnsSurfaceTheConversationSoFar() async throws {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let id = Self.seedEndedSession(sessions: sessions, turns: turns)
        let (engine, _) = Self.makeEngine(sessions: sessions, turns: turns)

        try await engine.resume(sessionId: id)
        let stored = try await engine.storedTurns()
        #expect(stored.map(\.text) == [
            "Morning.",
            "I finished the deploy yesterday.",
            "Good — any fallout?",
        ])
    }
}
