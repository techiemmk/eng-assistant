import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct SessionAnalyzerTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    final class FakeSessionPersister: SessionPersisting, @unchecked Sendable {
        var sessions: [UUID: Session] = [:]
        func create(_ session: Session) throws { sessions[session.id] = session }
        func find(id: UUID) throws -> Session? { sessions[id] }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {}
        func listActive() throws -> [Session] { Array(sessions.values) }
        func listRecent(limit: Int) throws -> [Session] {
            Array(sessions.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }
    }

    final class FakeTurnPersister: TurnPersisting, @unchecked Sendable {
        var turns: [Turn] = []
        var stored: [(turnId: UUID, json: String)] = []
        func append(_ turn: Turn) throws { turns.append(turn) }
        func list(forSession sessionId: UUID) throws -> [Turn] {
            turns.filter { $0.sessionId == sessionId }.sorted { $0.turnIndex < $1.turnIndex }
        }
        func markIncomplete(id: UUID) throws {}
        func updateMetricsJson(turnId: UUID, json: String) throws {
            stored.append((turnId, json))
        }
    }

    final class FakeWeakSpotPersister: WeakSpotPersisting, @unchecked Sendable {
        var store: [UUID: WeakSpot] = [:]
        func listActiveByFrequency(limit: Int) throws -> [WeakSpot] { Array(store.values).prefix(limit).map { $0 } }
        func create(_ ws: WeakSpot) throws { store[ws.id] = ws }
        func findByPattern(_ pattern: String) throws -> WeakSpot? {
            store.values.first { $0.pattern == pattern }
        }
        func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
            guard var ws = store[id] else { return }
            ws.occurrenceCount += 1; ws.lastSeen = lastSeen
            if let t = addExampleTurnId, !ws.exampleTurnIds.contains(t) {
                ws.exampleTurnIds.append(t)
            }
            store[id] = ws
        }
    }

    @Test func endToEndAnalysisProducesDebriefWithMetricsAndWeakSpots() async throws {
        let sessionPersister = FakeSessionPersister()
        let turnPersister = FakeTurnPersister()
        let weakSpotPersister = FakeWeakSpotPersister()
        let session = Session(
            id: UUID(), scenarioId: "test-01",
            startedAt: Date(), endedAt: Date(),
            mode: .flow, status: .ended,
            summary: nil, personaSnapshot: "Test persona."
        )
        try sessionPersister.create(session)
        try turnPersister.append(Turn(
            id: UUID(), sessionId: session.id, turnIndex: 0, speaker: .ai,
            text: "Hi.", audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        ))
        try turnPersister.append(Turn(
            id: UUID(), sessionId: session.id, turnIndex: 1, speaker: .user,
            text: "Um, I have finish the report yesterday.", audioPath: nil,
            startedAt: Date(), durationMs: 0, metricsJson: nil, isComplete: true
        ))
        try turnPersister.append(Turn(
            id: UUID(), sessionId: session.id, turnIndex: 2, speaker: .user,
            text: "I goes to office every day.", audioPath: nil,
            startedAt: Date(), durationMs: 0, metricsJson: nil, isComplete: true
        ))

        // GrammarJudge will be called twice (one per user turn). Then
        // WeakSpotExtractor is called once over the joined transcript.
        let llm = FakeLLMProvider(scriptedReplyBatches: [
            ["{\"grammarIssueCount\": 2}"],
            ["{\"grammarIssueCount\": 1}"],
            ["{\"patterns\":[{\"pattern\":\"present-perfect with past time\",\"category\":\"grammar\"}]}"],
        ])

        let analyzer = SessionAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotExtractor: WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotMerger: WeakSpotMerger(persister: weakSpotPersister),
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            scenarioCatalog: try ScenarioCatalog.loadBuiltIn()
        )

        let debrief = try await analyzer.analyze(sessionId: session.id)
        #expect(debrief.session.id == session.id)
        #expect(debrief.sessionMetrics.userTurnCount == 2)
        #expect(debrief.sessionMetrics.totalGrammarIssues == 3)
        #expect(debrief.newlyCreatedWeakSpots.count == 1)
        #expect(debrief.newlyCreatedWeakSpots[0].pattern == "present-perfect with past time")
        #expect(debrief.recurringWeakSpots.isEmpty)
        #expect(turnPersister.stored.count == 2)
    }

    @Test func missingSessionThrows() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{}"])
        let analyzer = SessionAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotExtractor: WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotMerger: WeakSpotMerger(persister: FakeWeakSpotPersister()),
            sessionPersister: FakeSessionPersister(),
            turnPersister: FakeTurnPersister(),
            scenarioCatalog: try ScenarioCatalog.loadBuiltIn()
        )
        await #expect(throws: SessionAnalyzerError.self) {
            _ = try await analyzer.analyze(sessionId: UUID())
        }
    }
}
