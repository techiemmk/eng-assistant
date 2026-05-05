import Testing
import Foundation
import Core
@testable import Core

@Suite struct WeakSpotMergerTests {
    final class InMemoryWeakSpotPersister: WeakSpotPersisting, @unchecked Sendable {
        var store: [UUID: WeakSpot] = [:]
        func listActiveByFrequency(limit: Int) throws -> [WeakSpot] {
            store.values.filter { $0.status == .active }
                .sorted { $0.occurrenceCount > $1.occurrenceCount }
                .prefix(limit).map { $0 }
        }
        func create(_ ws: WeakSpot) throws { store[ws.id] = ws }
        func findByPattern(_ pattern: String) throws -> WeakSpot? {
            store.values.first { $0.pattern == pattern }
        }
        func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
            guard var ws = store[id] else { return }
            ws.occurrenceCount += 1
            ws.lastSeen = lastSeen
            if let t = addExampleTurnId, !ws.exampleTurnIds.contains(t) {
                ws.exampleTurnIds.append(t)
            }
            store[id] = ws
        }
    }

    @Test func newPatternIsCreated() async throws {
        let store = InMemoryWeakSpotPersister()
        let merger = WeakSpotMerger(persister: store)
        let now = Date()
        let candidates = [WeakSpotCandidate(pattern: "uses 'more better'", category: .grammar)]
        let result = try merger.merge(
            candidates: candidates,
            sessionUserTurnIds: [UUID()],
            now: now
        )
        #expect(result.newlyCreated.count == 1)
        #expect(result.recurring.isEmpty)
        #expect(store.store.count == 1)
        #expect(store.store.values.first?.occurrenceCount == 1)
    }

    @Test func existingPatternIsIncremented() async throws {
        let store = InMemoryWeakSpotPersister()
        let now = Date()
        let existingId = UUID()
        try store.create(WeakSpot(
            id: existingId, pattern: "uses 'more better'", category: .grammar,
            firstSeen: now.addingTimeInterval(-86400), lastSeen: now.addingTimeInterval(-86400),
            occurrenceCount: 2, status: .active, exampleTurnIds: []
        ))
        let merger = WeakSpotMerger(persister: store)
        let candidates = [WeakSpotCandidate(pattern: "uses 'more better'", category: .grammar)]
        let exampleTurnId = UUID()
        let result = try merger.merge(
            candidates: candidates,
            sessionUserTurnIds: [exampleTurnId],
            now: now
        )
        #expect(result.newlyCreated.isEmpty)
        #expect(result.recurring.count == 1)
        let updated = try store.findByPattern("uses 'more better'")!
        #expect(updated.occurrenceCount == 3)
        #expect(updated.exampleTurnIds.contains(exampleTurnId))
    }

    @Test func mixOfNewAndRecurring() async throws {
        let store = InMemoryWeakSpotPersister()
        try store.create(WeakSpot(
            id: UUID(), pattern: "p-old", category: .grammar,
            firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 1, status: .active, exampleTurnIds: []
        ))
        let merger = WeakSpotMerger(persister: store)
        let candidates = [
            WeakSpotCandidate(pattern: "p-old", category: .grammar),
            WeakSpotCandidate(pattern: "p-new", category: .vocab),
        ]
        let result = try merger.merge(
            candidates: candidates,
            sessionUserTurnIds: [UUID()],
            now: Date()
        )
        #expect(result.newlyCreated.map(\.pattern) == ["p-new"])
        #expect(result.recurring.map(\.pattern) == ["p-old"])
    }

    @Test func emptyCandidatesReturnsEmptyResult() async throws {
        let store = InMemoryWeakSpotPersister()
        let merger = WeakSpotMerger(persister: store)
        let result = try merger.merge(candidates: [], sessionUserTurnIds: [], now: Date())
        #expect(result.newlyCreated.isEmpty)
        #expect(result.recurring.isEmpty)
    }
}
