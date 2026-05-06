import Testing
import Foundation
import Core
@testable import EngAssistantApp

@MainActor
@Suite struct SessionsHistoryViewModelTests {
    final class CapturingSessionPersister: SessionPersisting, @unchecked Sendable {
        var sessions: [Session] = []
        func create(_ session: Session) throws { sessions.append(session) }
        func find(id: UUID) throws -> Session? { sessions.first { $0.id == id } }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {}
        func listActive() throws -> [Session] { sessions.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] {
            Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }
    }

    @Test func loadsRecentSessionsSortedNewestFirst() async throws {
        let persister = CapturingSessionPersister()
        persister.sessions = [
            Session(id: UUID(), scenarioId: "a",
                    startedAt: Date(timeIntervalSince1970: 1_000),
                    endedAt: nil, mode: .flow, status: .ended,
                    summary: "old", personaSnapshot: "p"),
            Session(id: UUID(), scenarioId: "b",
                    startedAt: Date(timeIntervalSince1970: 5_000),
                    endedAt: nil, mode: .flow, status: .ended,
                    summary: "newer", personaSnapshot: "p"),
            Session(id: UUID(), scenarioId: "c",
                    startedAt: Date(timeIntervalSince1970: 3_000),
                    endedAt: nil, mode: .flow, status: .ended,
                    summary: "middle", personaSnapshot: "p"),
        ]
        let vm = SessionsHistoryViewModel(persister: persister)
        try await vm.load()
        #expect(vm.sessions.map(\.summary) == ["newer", "middle", "old"])
    }
}
