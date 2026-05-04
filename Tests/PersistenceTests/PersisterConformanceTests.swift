import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct PersisterConformanceTests {
    @Test func sessionRepositoryConformsToSessionPersisting() throws {
        let db = try Database.inMemory()
        let repo: any SessionPersisting = SessionRepository(database: db)
        let id = UUID()
        try repo.create(Session(
            id: id,
            scenarioId: "s",
            startedAt: Date(),
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "p"
        ))
        #expect(try repo.find(id: id)?.id == id)
    }

    @Test func turnRepositoryConformsToTurnPersisting() throws {
        let db = try Database.inMemory()
        let sessionRepo = SessionRepository(database: db)
        let sessionId = UUID()
        try sessionRepo.create(Session(
            id: sessionId, scenarioId: "s", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        ))
        let repo: any TurnPersisting = TurnRepository(database: db)
        try repo.append(Turn(
            id: UUID(), sessionId: sessionId, turnIndex: 0, speaker: .user,
            text: "hi", audioPath: nil, startedAt: Date(),
            durationMs: 100, metricsJson: nil, isComplete: true
        ))
        #expect(try repo.list(forSession: sessionId).count == 1)
    }

    @Test func weakSpotRepositoryConformsToWeakSpotPersisting() throws {
        let db = try Database.inMemory()
        let repo: any WeakSpotPersisting = WeakSpotRepository(database: db)
        #expect(try repo.listActiveByFrequency(limit: 5).isEmpty)
    }
}
