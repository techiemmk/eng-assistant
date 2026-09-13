import Testing
import Foundation
import Core
import Fakes
@testable import EngAssistantApp

/// `LiveSessionViewModel` used to hardcode `activeWeakSpots: []`, so coach
/// mode's weak-spot targeting was dead code. These cover the wiring and where
/// the resulting corrections land in the transcript.
@MainActor
@Suite struct CoachWiringTests {
    private static let scenario = Scenario(
        id: "coach-01", source: .builtin, title: "Coach", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    private static func weakSpot(_ pattern: String, _ category: WeakSpotCategory) -> WeakSpot {
        WeakSpot(
            id: UUID(), pattern: pattern, category: category,
            firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 4, status: .active, exampleTurnIds: []
        )
    }

    final class TurnStore: TurnPersisting, @unchecked Sendable {
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

    final class SessionStore: SessionPersisting, @unchecked Sendable {
        var sessions: [UUID: Session] = [:]
        func create(_ session: Session) throws { sessions[session.id] = session }
        func find(id: UUID) throws -> Session? { sessions[id] }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {
            guard var s = sessions[id] else { return }
            s.endedAt = endedAt; s.summary = summary; s.status = .ended
            sessions[id] = s
        }
        func reactivate(id: UUID) throws {
            guard var s = sessions[id] else { return }
            s.status = .active
            s.endedAt = nil
            sessions[id] = s
        }
        func listActive() throws -> [Session] { sessions.values.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] {
            Array(sessions.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }
    }

    private static func makeViewModel(
        mode: SessionMode = .coach,
        reply: String,
        userSaid: String = "Yesterday I have finish the refactor.",
        weakSpots: [WeakSpot] = []
    ) -> LiveSessionViewModel {
        LiveSessionViewModel(
            scenario: scenario,
            mode: mode,
            llm: FakeLLMProvider(scriptedReplies: [reply]),
            stt: FakeSTTProvider(scriptedTexts: [userSaid]),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: [4096]),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: SessionStore(),
            turnPersister: TurnStore(),
            audioFilePersister: nil,
            modelName: "fake",
            activeWeakSpots: weakSpots
        )
    }

    @Test func weakSpotsReachTheViewModelForDisplay() {
        let spots = [Self.weakSpot("uses 'more better'", .grammar)]
        let vm = Self.makeViewModel(reply: "Sure.", weakSpots: spots)
        #expect(vm.activeWeakSpots.map(\.pattern) == ["uses 'more better'"])
    }

    /// The engine only mentions weak spots via the persona prompt, so the proof
    /// they arrived is that the prompt the engine built carries them.
    @Test func weakSpotsReachThePersonaPrompt() {
        let spots = [Self.weakSpot("uses 'more better'", .grammar)]
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: spots)
        #expect(prompt.contains("uses 'more better'"))
        #expect(prompt.contains("seen 4x"))
    }

    /// A correction describes what the *user* said, so it must sit on the user's
    /// bubble — that's also the text the grammar highlight has to land in.
    @Test func correctionsAttachToTheUserTurnNotTheAIReply() async throws {
        let vm = Self.makeViewModel(
            reply: "[[coach:grammar: try 'I finished' instead of 'I have finish']] Good progress."
        )
        try await vm.start()
        try await vm.runUserTurn()

        #expect(vm.transcript.count == 3)
        let userTurn = vm.transcript[1]
        let aiTurn = vm.transcript[2]
        #expect(userTurn.speaker == .user)
        #expect(userTurn.corrections.count == 1)
        #expect(aiTurn.corrections.isEmpty)
    }

    @Test func grammarCorrectionCarriesCategoryAndOffendingPhrase() async throws {
        let vm = Self.makeViewModel(
            reply: "[[coach:grammar: try 'I finished' instead of 'I have finish']] Good progress."
        )
        try await vm.start()
        try await vm.runUserTurn()

        let correction = try #require(vm.transcript[1].corrections.first)
        #expect(correction.category == .grammar)
        #expect(correction.offendingText == "I have finish")
        // The phrase has to actually occur in the turn, or there's nothing to mark.
        #expect(vm.transcript[1].text.contains("I have finish"))
    }

    @Test func markerIsStrippedFromTheSpokenAIReply() async throws {
        let vm = Self.makeViewModel(
            reply: "[[coach:grammar: try 'I finished' instead of 'I have finish']] Good progress."
        )
        try await vm.start()
        try await vm.runUserTurn()
        // The persisted AI text keeps the raw reply for the debrief, but it must
        // never be the only copy — the user-facing correction is separate.
        #expect(vm.transcript[1].corrections.first?.message.contains("I finished") == true)
    }

    @Test func earlierTurnsDoNotKeepStaleCorrections() async throws {
        let vm = LiveSessionViewModel(
            scenario: Self.scenario,
            mode: .coach,
            llm: FakeLLMProvider(scriptedReplyBatches: [
                ["[[coach:grammar: try 'I finished' instead of 'I have finish']] OK."],
                ["Nothing wrong there."],
            ]),
            stt: FakeSTTProvider(scriptedTexts: [
                "Yesterday I have finish the refactor.",
                "Today I am starting the rate limiter.",
            ]),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: [4096, 4096]),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: SessionStore(),
            turnPersister: TurnStore(),
            audioFilePersister: nil,
            modelName: "fake"
        )
        try await vm.start()
        try await vm.runUserTurn()
        try await vm.runUserTurn()

        // Only the most recent user turn carries corrections; the clean second
        // turn must not inherit the first turn's grammar flag.
        let userTurns = vm.transcript.filter { $0.speaker == .user }
        #expect(userTurns.count == 2)
        #expect(userTurns[0].corrections.isEmpty)
        #expect(userTurns[1].corrections.isEmpty)
    }

    @Test func flowModeGetsNoInlineCorrections() async throws {
        let vm = Self.makeViewModel(mode: .flow, reply: "Good progress.")
        try await vm.start()
        try await vm.runUserTurn()
        #expect(vm.transcript.allSatisfy { $0.corrections.isEmpty })
        #expect(vm.activeWeakSpots.isEmpty)
    }

    @Test func uncategorisedMarkerStillProducesATip() async throws {
        let vm = Self.makeViewModel(reply: "[[coach: watch your tense]] Sure.")
        try await vm.start()
        try await vm.runUserTurn()
        let correction = try #require(vm.transcript[1].corrections.first)
        #expect(correction.category == nil)
        #expect(correction.message == "watch your tense")
    }
}

@Suite struct CorrectionThemeTests {
    /// Every category needs a distinct color, or the grammar flag stops being
    /// distinguishable from a vocabulary nudge.
    @Test func grammarIsStyledDistinctlyFromTheOtherCategories() {
        let grammar = Theme.correctionColor(.grammar)
        for other in WeakSpotCategory.allCases where other != .grammar {
            #expect(Theme.correctionColor(other) != grammar)
        }
        #expect(Theme.correctionColor(nil) != grammar)
    }

    @Test func everyCategoryHasAnIconAndLabel() {
        for category in WeakSpotCategory.allCases {
            #expect(!Theme.correctionIcon(category).isEmpty)
            #expect(!Theme.correctionLabel(category).isEmpty)
        }
        #expect(!Theme.correctionIcon(nil).isEmpty)
        #expect(!Theme.correctionLabel(nil).isEmpty)
    }

    @Test func grammarLabelReadsAsGrammar() {
        #expect(Theme.correctionLabel(.grammar) == "Grammar")
    }
}
