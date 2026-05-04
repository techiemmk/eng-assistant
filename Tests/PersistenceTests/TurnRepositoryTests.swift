import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct TurnRepositoryTests {
    private static func setup() throws -> (TurnRepository, SessionRepository, UUID) {
        let db = try Database.inMemory()
        let sessionRepo = SessionRepository(database: db)
        let turnRepo = TurnRepository(database: db)
        let sessionId = UUID()
        try sessionRepo.create(Session(
            id: sessionId,
            scenarioId: "work-standup-01",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "test"
        ))
        return (turnRepo, sessionRepo, sessionId)
    }

    private static func makeTurn(sessionId: UUID, index: Int, speaker: Speaker, complete: Bool = true) -> Turn {
        Turn(
            id: UUID(),
            sessionId: sessionId,
            turnIndex: index,
            speaker: speaker,
            text: "Sample text \(index)",
            audioPath: speaker == .user ? "audio/x/user-turn-\(index).wav" : nil,
            startedAt: Date(timeIntervalSince1970: 1_777_000_000 + Double(index * 10)),
            durationMs: 3000,
            metricsJson: nil,
            isComplete: complete
        )
    }

    @Test func appendAndList() throws {
        let (turnRepo, _, sessionId) = try Self.setup()
        try turnRepo.append(Self.makeTurn(sessionId: sessionId, index: 0, speaker: .user))
        try turnRepo.append(Self.makeTurn(sessionId: sessionId, index: 1, speaker: .ai))
        let turns = try turnRepo.list(forSession: sessionId)
        #expect(turns.count == 2)
        #expect(turns.map(\.turnIndex) == [0, 1])
    }

    @Test func markIncomplete() throws {
        let (turnRepo, _, sessionId) = try Self.setup()
        let t = Self.makeTurn(sessionId: sessionId, index: 0, speaker: .ai, complete: true)
        try turnRepo.append(t)
        try turnRepo.markIncomplete(id: t.id)
        let turns = try turnRepo.list(forSession: sessionId)
        #expect(turns.first?.isComplete == false)
    }

    @Test func findIncompleteTurnsForSession() throws {
        let (turnRepo, _, sessionId) = try Self.setup()
        try turnRepo.append(Self.makeTurn(sessionId: sessionId, index: 0, speaker: .user, complete: true))
        try turnRepo.append(Self.makeTurn(sessionId: sessionId, index: 1, speaker: .ai, complete: false))
        let incomplete = try turnRepo.listIncomplete(forSession: sessionId)
        #expect(incomplete.count == 1)
        #expect(incomplete.first?.turnIndex == 1)
    }

    @Test func updateMetricsJson() throws {
        let (turnRepo, _, sessionId) = try Self.setup()
        let t = Self.makeTurn(sessionId: sessionId, index: 0, speaker: .user)
        try turnRepo.append(t)
        try turnRepo.updateMetricsJson(turnId: t.id, json: "{\"wordsPerMinute\":120}")
        let turns = try turnRepo.list(forSession: sessionId)
        #expect(turns.first?.metricsJson == "{\"wordsPerMinute\":120}")
    }
}
