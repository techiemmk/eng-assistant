import Testing
import Foundation
import Core
@testable import Persistence

/// The debrief cache is what makes analysis safe to call twice, so it gets
/// tested against the real database rather than a double.
@Suite struct DebriefRepositoryTests {
    private static func makeDebrief(sessionId: UUID = UUID(), summary: String = "s") -> Debrief {
        let session = Session(
            id: sessionId, scenarioId: "work-standup-01", startedAt: Date(),
            endedAt: Date(), mode: .flow, status: .ended, summary: summary,
            personaSnapshot: "p"
        )
        let scenario = Scenario(
            id: "work-standup-01", source: .builtin, title: "Standup", domain: .workplace,
            persona: "p", openingLine: "hi", difficulty: 2, tags: [], notes: nil
        )
        return Debrief(
            session: session,
            scenario: scenario,
            summary: summary,
            allTurns: [],
            sessionMetrics: SessionMetrics(
                userTurnCount: 1, totalWordCount: 10, totalFillerCount: 0,
                totalGrammarIssues: 1, averageUniqueWordRatio: 0.9,
                averageFillerDensity: 0.0
            ),
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: [],
            suggestedDrills: ["drill one"]
        )
    }

    @Test func savesAndReadsBackADebrief() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let repo = DebriefRepository(database: db)
        let debrief = Self.makeDebrief()
        try sessions.create(debrief.session)

        try repo.save(debrief)

        let found = try repo.find(sessionId: debrief.session.id)
        #expect(found == debrief)
    }

    @Test func findReturnsNilForAnUnanalysedSession() throws {
        let db = try Database.inMemory()
        #expect(try DebriefRepository(database: db).find(sessionId: UUID()) == nil)
    }

    /// Re-analysis overwrites rather than failing on the primary key.
    @Test func savingTwiceReplacesTheStoredDebrief() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let repo = DebriefRepository(database: db)
        let id = UUID()
        try sessions.create(Self.makeDebrief(sessionId: id, summary: "first").session)

        try repo.save(Self.makeDebrief(sessionId: id, summary: "first"))
        try repo.save(Self.makeDebrief(sessionId: id, summary: "second"))

        #expect(try repo.find(sessionId: id)?.summary == "second")
    }

    /// Deleting a session must not leave its debrief behind — that's storage
    /// that nothing can ever reach again.
    @Test func deletingASessionRemovesItsCachedDebrief() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let repo = DebriefRepository(database: db)
        let debrief = Self.makeDebrief()
        try sessions.create(debrief.session)
        try repo.save(debrief)

        try sessions.delete(id: debrief.session.id)

        #expect(try repo.find(sessionId: debrief.session.id) == nil)
    }

    @Test func deleteRemovesOnlyTheNamedDebrief() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let repo = DebriefRepository(database: db)
        let doomed = Self.makeDebrief()
        let keeper = Self.makeDebrief()
        try sessions.create(doomed.session)
        try sessions.create(keeper.session)
        try repo.save(doomed)
        try repo.save(keeper)

        try repo.delete(sessionId: doomed.session.id)

        #expect(try repo.find(sessionId: doomed.session.id) == nil)
        #expect(try repo.find(sessionId: keeper.session.id) != nil)
    }
}

@Suite struct SessionAbandonTests {
    @Test func abandonMarksTheSessionAndStopsItBeingActive() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let session = Session(
            id: UUID(), scenarioId: "s", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        )
        try sessions.create(session)
        #expect(try sessions.listActive().count == 1)

        try sessions.abandon(id: session.id)

        #expect(try sessions.find(id: session.id)?.status == .abandoned)
        #expect(try sessions.listActive().isEmpty, "an abandoned session must stop being offered")
        #expect(try sessions.find(id: session.id)?.endedAt != nil)
    }

    /// It should still appear in history — abandoned is a record, not a delete.
    @Test func abandonedSessionsStayInHistory() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let session = Session(
            id: UUID(), scenarioId: "s", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        )
        try sessions.create(session)
        try sessions.abandon(id: session.id)
        #expect(try sessions.listRecent(limit: 10).count == 1)
    }
}
