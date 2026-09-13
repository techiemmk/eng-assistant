import Testing
import Foundation
import Core
import Fakes
@testable import EngAssistantApp

/// The session screen's side of resuming: the transcript has to show the
/// earlier conversation, and the next turn has to append to it.
@MainActor
@Suite struct LiveSessionResumeTests {
    private static let scenario = Scenario(
        id: "resume-vm-01", source: .builtin, title: "Resume", domain: .work,
        persona: "Test persona.", openingLine: "Morning.",
        difficulty: 2, tags: [], notes: nil
    )

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
        func delete(id: UUID) throws { sessions[id] = nil }
        func listActive() throws -> [Session] { sessions.values.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] {
            Array(sessions.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }
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

    private static func seed(_ sessions: SessionStore, _ turns: TurnStore) -> UUID {
        let id = UUID()
        try! sessions.create(Session(
            id: id, scenarioId: scenario.id, startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2000), mode: .flow, status: .ended,
            summary: "earlier", personaSnapshot: scenario.persona
        ))
        for (index, entry) in [(Speaker.ai, "Morning."),
                               (Speaker.user, "I shipped the deploy."),
                               (Speaker.ai, "Any fallout?")].enumerated() {
            try! turns.append(Turn(
                id: UUID(), sessionId: id, turnIndex: index, speaker: entry.0,
                text: entry.1, audioPath: nil, startedAt: Date(), durationMs: 0,
                metricsJson: nil, isComplete: true
            ))
        }
        return id
    }

    private static func makeViewModel(
        sessions: SessionStore,
        turns: TurnStore
    ) -> LiveSessionViewModel {
        LiveSessionViewModel(
            scenario: scenario,
            mode: .flow,
            llm: FakeLLMProvider(scriptedReplies: ["Nothing broke."]),
            stt: FakeSTTProvider(scriptedTexts: ["No, it was clean."]),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: [4096]),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: sessions,
            turnPersister: turns,
            audioFilePersister: nil,
            modelName: "fake"
        )
    }

    @Test func resumeShowsTheEarlierConversation() async throws {
        let sessions = SessionStore(); let turns = TurnStore()
        let id = Self.seed(sessions, turns)
        let vm = Self.makeViewModel(sessions: sessions, turns: turns)

        try await vm.resume(sessionId: id)

        #expect(vm.transcript.map(\.text) == ["Morning.", "I shipped the deploy.", "Any fallout?"])
        #expect(vm.isActive)
        #expect(vm.isResumed)
        #expect(vm.lastError == nil)
    }

    /// A fresh start shows only the opening line and isn't flagged as resumed.
    @Test func startIsNotFlaggedAsResumed() async throws {
        let sessions = SessionStore(); let turns = TurnStore()
        let vm = Self.makeViewModel(sessions: sessions, turns: turns)
        try await vm.start()
        #expect(vm.isResumed == false)
        #expect(vm.transcript.count == 1)
    }

    @Test func aTurnAfterResumingAppendsToTheExistingTranscript() async throws {
        let sessions = SessionStore(); let turns = TurnStore()
        let id = Self.seed(sessions, turns)
        let vm = Self.makeViewModel(sessions: sessions, turns: turns)

        try await vm.resume(sessionId: id)
        try await vm.runUserTurn()

        #expect(vm.transcript.count == 5)
        #expect(vm.transcript[3].speaker == .user)
        #expect(vm.transcript[3].text == "No, it was clean.")
        #expect(vm.transcript[4].text == "Nothing broke.")
    }

    /// Ending a resumed session shouldn't fork a new one.
    @Test func endingAResumedSessionKeepsTheSameId() async throws {
        let sessions = SessionStore(); let turns = TurnStore()
        let id = Self.seed(sessions, turns)
        let vm = Self.makeViewModel(sessions: sessions, turns: turns)

        try await vm.resume(sessionId: id)
        let endedId = try await vm.end()

        #expect(endedId == id)
        #expect(sessions.sessions.count == 1)
        #expect(sessions.sessions[id]?.status == .ended)
    }

    @Test func resumingAMissingSessionSurfacesAFriendlyError() async throws {
        let sessions = SessionStore(); let turns = TurnStore()
        let vm = Self.makeViewModel(sessions: sessions, turns: turns)

        await #expect(throws: (any Error).self) {
            try await vm.resume(sessionId: UUID())
        }
        #expect(vm.lastError?.contains("couldn't be found") == true)
        #expect(vm.isActive == false)
    }
}

@MainActor
@Suite struct SessionHistoryTitleTests {
    final class Store: SessionPersisting, @unchecked Sendable {
        var sessions: [Session] = []
        func create(_ session: Session) throws { sessions.append(session) }
        func find(id: UUID) throws -> Session? { sessions.first { $0.id == id } }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {}
        func reactivate(id: UUID) throws {}
        func delete(id: UUID) throws { sessions.removeAll { $0.id == id } }
        func listActive() throws -> [Session] { sessions.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] { Array(sessions.prefix(limit)) }
    }

    private static func session(scenarioId: String) -> Session {
        Session(id: UUID(), scenarioId: scenarioId, startedAt: Date(), endedAt: nil,
                mode: .flow, status: .ended, summary: nil, personaSnapshot: "p")
    }

    /// Rows used to print the raw scenario id, which makes Continue guesswork.
    @Test func rowsShowTheScenarioTitle() throws {
        let vm = SessionsHistoryViewModel(
            persister: Store(),
            catalog: try ScenarioCatalog.loadBuiltIn()
        )
        let title = vm.title(for: Self.session(scenarioId: "work-standup-01"))
        #expect(title == "Daily Engineering Standup")
    }

    @Test func rowsFallBackToTheIdForAMissingScenario() throws {
        let vm = SessionsHistoryViewModel(
            persister: Store(),
            catalog: try ScenarioCatalog.loadBuiltIn()
        )
        let session = Self.session(scenarioId: "deleted-scenario")
        #expect(vm.title(for: session) == "deleted-scenario")
        #expect(vm.canContinue(session) == false)
    }

    @Test func continueIsOfferedForAKnownScenario() throws {
        let vm = SessionsHistoryViewModel(
            persister: Store(),
            catalog: try ScenarioCatalog.loadBuiltIn()
        )
        #expect(vm.canContinue(Self.session(scenarioId: "work-clinic-mdt-01")))
    }
}
