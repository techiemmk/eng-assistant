import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct WeakSpotRepositoryTests {
    private static func makeRepo() throws -> WeakSpotRepository {
        WeakSpotRepository(database: try Database.inMemory())
    }

    private static let now = Date(timeIntervalSince1970: 1_777_000_000)

    @Test func createAndFindByPattern() throws {
        let repo = try Self.makeRepo()
        let ws = WeakSpot(
            id: UUID(),
            pattern: "uses 'more better' instead of 'better'",
            category: .grammar,
            firstSeen: Self.now,
            lastSeen: Self.now,
            occurrenceCount: 1,
            status: .active,
            exampleTurnIds: [UUID()]
        )
        try repo.create(ws)
        let found = try repo.findByPattern(ws.pattern)
        #expect(found?.id == ws.id)
    }

    @Test func incrementOccurrence() throws {
        let repo = try Self.makeRepo()
        let ws = WeakSpot(
            id: UUID(),
            pattern: "stutters on conditionals",
            category: .fluency,
            firstSeen: Self.now,
            lastSeen: Self.now,
            occurrenceCount: 1,
            status: .active,
            exampleTurnIds: []
        )
        try repo.create(ws)
        let later = Self.now.addingTimeInterval(60)
        let newTurnId = UUID()
        try repo.incrementOccurrence(id: ws.id, lastSeen: later, addExampleTurnId: newTurnId)
        let updated = try repo.findByPattern(ws.pattern)
        #expect(updated?.occurrenceCount == 2)
        #expect(updated?.lastSeen == later)
        #expect(updated?.exampleTurnIds == [newTurnId])
    }

    @Test func listActiveByFrequency() throws {
        let repo = try Self.makeRepo()
        let a = WeakSpot(id: UUID(), pattern: "p1", category: .grammar, firstSeen: Self.now, lastSeen: Self.now,
                         occurrenceCount: 1, status: .active, exampleTurnIds: [])
        let b = WeakSpot(id: UUID(), pattern: "p2", category: .grammar, firstSeen: Self.now, lastSeen: Self.now,
                         occurrenceCount: 5, status: .active, exampleTurnIds: [])
        let c = WeakSpot(id: UUID(), pattern: "p3", category: .grammar, firstSeen: Self.now, lastSeen: Self.now,
                         occurrenceCount: 3, status: .resolved, exampleTurnIds: [])
        try repo.create(a); try repo.create(b); try repo.create(c)
        let active = try repo.listActiveByFrequency(limit: 10)
        #expect(active.map(\.pattern) == ["p2", "p1"])
    }

    @Test func markResolved() throws {
        let repo = try Self.makeRepo()
        let ws = WeakSpot(id: UUID(), pattern: "p1", category: .filler,
                          firstSeen: Self.now, lastSeen: Self.now,
                          occurrenceCount: 1, status: .active, exampleTurnIds: [])
        try repo.create(ws)
        try repo.markResolved(id: ws.id)
        let found = try repo.findByPattern("p1")
        #expect(found?.status == .resolved)
    }
}
