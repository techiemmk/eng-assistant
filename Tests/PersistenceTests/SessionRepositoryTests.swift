import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct SessionRepositoryTests {
    private static func makeRepo() throws -> (SessionRepository, Database) {
        let db = try Database.inMemory()
        let repo = SessionRepository(database: db)
        return (repo, db)
    }

    private static func makeSession(id: UUID = UUID(),
                                    status: SessionStatus = .active,
                                    ended: Date? = nil) -> Session {
        Session(
            id: id,
            scenarioId: "work-standup-01",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: ended,
            mode: .flow,
            status: status,
            summary: nil,
            personaSnapshot: "A no-nonsense engineering manager."
        )
    }

    @Test func createAndFetchById() throws {
        let (repo, _) = try Self.makeRepo()
        let s = Self.makeSession()
        try repo.create(s)
        let fetched = try repo.find(id: s.id)
        #expect(fetched == s)
    }

    @Test func findByIdMissingReturnsNil() throws {
        let (repo, _) = try Self.makeRepo()
        #expect(try repo.find(id: UUID()) == nil)
    }

    @Test func finalizeUpdatesEndedAndStatus() throws {
        let (repo, _) = try Self.makeRepo()
        let s = Self.makeSession()
        try repo.create(s)
        let endTime = Date(timeIntervalSince1970: 1_777_001_000)
        try repo.finalize(id: s.id, endedAt: endTime, summary: "Discussed Q2 goals.")
        let fetched = try repo.find(id: s.id)
        #expect(fetched?.status == .ended)
        #expect(fetched?.endedAt == endTime)
        #expect(fetched?.summary == "Discussed Q2 goals.")
    }

    @Test func findOrphanedReturnsActiveOnly() throws {
        let (repo, _) = try Self.makeRepo()
        let active = Self.makeSession(status: .active)
        let ended = Self.makeSession(id: UUID(), status: .ended, ended: Date())
        try repo.create(active)
        try repo.create(ended)
        let orphans = try repo.findOrphaned()
        #expect(orphans.count == 1)
        #expect(orphans.first?.id == active.id)
    }

    @Test func listByDateRange() throws {
        let (repo, _) = try Self.makeRepo()
        let early = Self.makeSession(id: UUID())
        let late = Session(
            id: UUID(),
            scenarioId: "work-standup-01",
            startedAt: Date(timeIntervalSince1970: 1_777_100_000),
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "test"
        )
        try repo.create(early)
        try repo.create(late)
        let results = try repo.list(
            from: Date(timeIntervalSince1970: 1_777_050_000),
            to: Date(timeIntervalSince1970: 1_777_200_000)
        )
        #expect(results.count == 1)
        #expect(results.first?.id == late.id)
    }
}
