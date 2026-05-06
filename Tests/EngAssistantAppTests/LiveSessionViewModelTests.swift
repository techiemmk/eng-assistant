import Testing
import Foundation
import Core
import Fakes
@testable import EngAssistantApp

@MainActor
@Suite struct LiveSessionViewModelTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    final class CapturingSessionPersister: SessionPersisting, @unchecked Sendable {
        var sessions: [UUID: Session] = [:]
        func create(_ session: Session) throws { sessions[session.id] = session }
        func find(id: UUID) throws -> Session? { sessions[id] }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {
            guard var s = sessions[id] else { return }
            s.endedAt = endedAt; s.summary = summary; s.status = .ended
            sessions[id] = s
        }
        func listActive() throws -> [Session] { sessions.values.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] {
            Array(sessions.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }
    }

    final class CapturingTurnPersister: TurnPersisting, @unchecked Sendable {
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

    @Test func startCreatesSessionAndAppendsOpeningTurn() async throws {
        let sp = CapturingSessionPersister()
        let tp = CapturingTurnPersister()
        let vm = LiveSessionViewModel(
            scenario: Self.scenario,
            mode: .flow,
            llm: FakeLLMProvider(scriptedReplies: ["x"]),
            stt: FakeSTTProvider(scriptedTexts: []),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: []),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: sp,
            turnPersister: tp,
            audioFilePersister: nil
        )
        try await vm.start()
        #expect(vm.transcript.count == 1)
        #expect(vm.transcript.first?.speaker == .ai)
        #expect(vm.transcript.first?.text == "Hi.")
        #expect(vm.isActive)
    }

    @Test func runUserTurnAppendsTwoTurnsToTranscript() async throws {
        let sp = CapturingSessionPersister()
        let tp = CapturingTurnPersister()
        let vm = LiveSessionViewModel(
            scenario: Self.scenario,
            mode: .flow,
            llm: FakeLLMProvider(scriptedReplies: ["I'm well, thanks."]),
            stt: FakeSTTProvider(scriptedTexts: ["Hello there."]),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: [100]),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: sp,
            turnPersister: tp,
            audioFilePersister: nil
        )
        try await vm.start()
        try await vm.runUserTurn()
        #expect(vm.transcript.count == 3)
        #expect(vm.transcript[1].speaker == .user)
        #expect(vm.transcript[1].text == "Hello there.")
        #expect(vm.transcript[2].speaker == .ai)
        #expect(vm.transcript[2].text == "I'm well, thanks.")
    }

    @Test func endSetsInactiveAndReturnsSessionId() async throws {
        let sp = CapturingSessionPersister()
        let tp = CapturingTurnPersister()
        let vm = LiveSessionViewModel(
            scenario: Self.scenario,
            mode: .flow,
            llm: FakeLLMProvider(scriptedReplies: ["x"]),
            stt: FakeSTTProvider(scriptedTexts: []),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: []),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: sp,
            turnPersister: tp,
            audioFilePersister: nil
        )
        try await vm.start()
        let id = try await vm.end()
        #expect(!vm.isActive)
        #expect(sp.sessions[id]?.status == .ended)
    }
}
