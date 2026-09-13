import Testing
import Foundation
import Core
@testable import Persistence

/// Deleting a session has to take its turns and its recordings with it —
/// leaving either behind means the storage grows forever and the debrief can
/// find turns for a session that no longer exists.
@Suite struct SessionDeletionTests {
    private static func makeSession(id: UUID = UUID(), scenarioId: String = "s1") -> Session {
        Session(
            id: id, scenarioId: scenarioId, startedAt: Date(), endedAt: nil,
            mode: .flow, status: .ended, summary: nil, personaSnapshot: "p"
        )
    }

    private static func makeTurn(sessionId: UUID, index: Int) -> Turn {
        Turn(
            id: UUID(), sessionId: sessionId, turnIndex: index, speaker: .user,
            text: "turn \(index)", audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        )
    }

    @Test func deleteRemovesTheSessionRow() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let session = Self.makeSession()
        try sessions.create(session)

        try sessions.delete(id: session.id)

        #expect(try sessions.find(id: session.id) == nil)
        #expect(try sessions.listRecent(limit: 10).isEmpty)
    }

    @Test func deleteRemovesTheSessionsTurns() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let turns = TurnRepository(database: db)
        let session = Self.makeSession()
        try sessions.create(session)
        for i in 0..<3 { try turns.append(Self.makeTurn(sessionId: session.id, index: i)) }
        #expect(try turns.list(forSession: session.id).count == 3)

        try sessions.delete(id: session.id)

        #expect(try turns.list(forSession: session.id).isEmpty)
    }

    /// Deleting one conversation must not touch another.
    @Test func deleteLeavesOtherSessionsIntact() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let turns = TurnRepository(database: db)
        let doomed = Self.makeSession()
        let keeper = Self.makeSession()
        try sessions.create(doomed)
        try sessions.create(keeper)
        try turns.append(Self.makeTurn(sessionId: doomed.id, index: 0))
        try turns.append(Self.makeTurn(sessionId: keeper.id, index: 0))

        try sessions.delete(id: doomed.id)

        #expect(try sessions.find(id: keeper.id) != nil)
        #expect(try turns.list(forSession: keeper.id).count == 1)
    }

    @Test func deletingAnUnknownSessionIsHarmless() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        try sessions.create(Self.makeSession())

        try sessions.delete(id: UUID())

        #expect(try sessions.listRecent(limit: 10).count == 1)
    }

    @Test func deletedSessionDropsOutOfTheActiveList() throws {
        let db = try Database.inMemory()
        let sessions = SessionRepository(database: db)
        let active = Session(
            id: UUID(), scenarioId: "s1", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        )
        try sessions.create(active)
        #expect(try sessions.listActive().count == 1)

        try sessions.delete(id: active.id)
        #expect(try sessions.listActive().isEmpty)
    }
}

@Suite struct AudioFileDeletionTests {
    private static func makeStore() -> (AudioFileStore, StorageLayout) {
        let layout = StorageLayout(appName: "EngAssistantTest-\(UUID().uuidString)")
        return (AudioFileStore(layout: layout), layout)
    }

    @Test func deleteAllRemovesEveryClipForTheSession() throws {
        let (store, layout) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }
        let sessionId = UUID()
        _ = try store.write(audio: Data(repeating: 1, count: 64), sessionId: sessionId,
                            turnIndex: 0, speaker: .ai)
        _ = try store.write(audio: Data(repeating: 2, count: 64), sessionId: sessionId,
                            turnIndex: 1, speaker: .user)
        let dir = layout.audioDirectory.appendingPathComponent(sessionId.uuidString)
        #expect(FileManager.default.fileExists(atPath: dir.path))

        try store.deleteAll(forSession: sessionId)

        #expect(FileManager.default.fileExists(atPath: dir.path) == false)
    }

    @Test func deleteAllLeavesOtherSessionsAudioAlone() throws {
        let (store, layout) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }
        let doomed = UUID()
        let keeper = UUID()
        _ = try store.write(audio: Data(repeating: 1, count: 64), sessionId: doomed,
                            turnIndex: 0, speaker: .ai)
        let keeperPath = try store.write(audio: Data(repeating: 1, count: 64), sessionId: keeper,
                                         turnIndex: 0, speaker: .ai)

        try store.deleteAll(forSession: doomed)

        let keeperURL = layout.rootDirectory.appendingPathComponent(keeperPath)
        #expect(FileManager.default.fileExists(atPath: keeperURL.path))
    }

    /// A session that never recorded anything still has to be deletable.
    @Test func deleteAllOnASessionWithNoAudioSucceeds() throws {
        let (store, layout) = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: layout.rootDirectory) }
        try store.deleteAll(forSession: UUID())
    }
}
