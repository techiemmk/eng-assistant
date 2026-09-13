import Testing
import Foundation
import Core
import Adapters
import Fakes
@testable import EngAssistantApp

/// Push-to-talk is now two taps (or one tap plus a pause). These cover the
/// listening state the button renders from, and the VAD auto-stop.
@MainActor
@Suite struct LiveSessionListeningTests {
    private static let scenario = Scenario(
        id: "listen-01", source: .builtin, title: "Listen", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    final class TurnStore: TurnPersisting, @unchecked Sendable {
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

    final class SessionStore: SessionPersisting, @unchecked Sendable {
        var sessions: [UUID: Session] = [:]
        func create(_ session: Session) throws { sessions[session.id] = session }
        func find(id: UUID) throws -> Session? { sessions[id] }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {
            guard var s = sessions[id] else { return }
            s.endedAt = endedAt; s.summary = summary; s.status = .ended
            sessions[id] = s
        }
        func reactivate(id: UUID) throws {
            guard var s = sessions[id] else { return }
            s.status = .active
            s.endedAt = nil
            sessions[id] = s
        }
        func delete(id: UUID) throws { sessions[id] = nil }
        func listActive() throws -> [Session] { sessions.values.filter { $0.status == .active } }
        func listRecent(limit: Int) throws -> [Session] {
            Array(sessions.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }
    }

    private static func makeViewModel(
        stt: STTProvider = FakeSTTProvider(scriptedTexts: ["Hello there."]),
        clipByteCounts: [Int] = [4096],
        endpointAfterPolls: Int? = nil,
        pollInterval: Duration = .milliseconds(10)
    ) -> LiveSessionViewModel {
        LiveSessionViewModel(
            scenario: scenario,
            mode: .flow,
            llm: FakeLLMProvider(scriptedReplies: ["Good to hear."]),
            stt: stt,
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(
                scriptedClipByteCounts: clipByteCounts,
                endpointAfterPolls: endpointAfterPolls
            ),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: SessionStore(),
            turnPersister: TurnStore(),
            audioFilePersister: nil,
            modelName: "fake",
            endpointPollInterval: pollInterval
        )
    }

    @Test func startListeningOpensTheMicAndHoldsIt() async throws {
        let vm = Self.makeViewModel()
        try await vm.start()
        await vm.startListening()
        #expect(vm.isListening)
        // Nothing transcribed yet — the user is still talking.
        #expect(vm.transcript.count == 1)
    }

    @Test func stopListeningRunsTheTurn() async throws {
        let vm = Self.makeViewModel()
        try await vm.start()
        await vm.startListening()
        await vm.stopListening()
        #expect(vm.isListening == false)
        #expect(vm.transcript.count == 3)
        #expect(vm.transcript[1].text == "Hello there.")
        #expect(vm.lastError == nil)
    }

    @Test func toggleListeningAlternates() async throws {
        let vm = Self.makeViewModel()
        try await vm.start()
        await vm.toggleListening()
        #expect(vm.isListening)
        await vm.toggleListening()
        #expect(vm.isListening == false)
        #expect(vm.transcript.count == 3)
    }

    /// The endpointer is what makes "just stop talking" work — before this, the
    /// VAD existed but nothing ever consulted it.
    @Test func vadEndpointAutoFinishesTheTurn() async throws {
        let vm = Self.makeViewModel(endpointAfterPolls: 2)
        try await vm.start()
        await vm.startListening()

        var waited = 0
        while vm.isListening && waited < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        #expect(vm.isListening == false)
        #expect(vm.transcript.count == 3)
    }

    @Test func listeningIsIgnoredBeforeTheSessionStarts() async {
        let vm = Self.makeViewModel()
        await vm.startListening()
        #expect(vm.isListening == false)
    }

    @Test func endingWhileListeningClosesTheMic() async throws {
        let vm = Self.makeViewModel()
        try await vm.start()
        await vm.startListening()
        _ = try await vm.end()
        #expect(vm.isListening == false)
        #expect(vm.isActive == false)
    }

    /// A missing Ollama model reached the UI as "Turn failed: statusCode(404)".
    @Test func missingModelSurfacesAnActionableMessage() async throws {
        let vm = LiveSessionViewModel(
            scenario: Self.scenario,
            mode: .flow,
            llm: FailingLLMProvider(error: OllamaLLMError.modelNotInstalled(model: "qwen2.5:7b-instruct")),
            stt: FakeSTTProvider(scriptedTexts: ["Hello there."]),
            tts: FakeTTSProvider(),
            audioCapture: FakeAudioCapture(scriptedClipByteCounts: [4096]),
            audioPlayback: FakeAudioPlayback(),
            sessionPersister: SessionStore(),
            turnPersister: TurnStore(),
            audioFilePersister: nil,
            modelName: "qwen2.5:7b-instruct"
        )
        try await vm.start()
        await vm.startListening()
        await vm.stopListening()

        let error = vm.lastError ?? ""
        #expect(error.contains("ollama pull qwen2.5:7b-instruct"))
        #expect(!error.contains("statusCode"))
    }

    /// Unconfigured speech-to-text used to return placeholder text, so the AI
    /// answered words the user never said. Now it says what's missing.
    @Test func unconfiguredSTTSurfacesSetupInstructions() async throws {
        let vm = Self.makeViewModel(stt: UnconfiguredSTTProvider())
        try await vm.start()
        await vm.startListening()
        await vm.stopListening()

        let error = vm.lastError ?? ""
        #expect(error.contains("whisper-cpp"))
        #expect(vm.transcript.count == 1)
    }

    @Test func silentClipSurfacesATryAgainMessage() async throws {
        let vm = Self.makeViewModel(clipByteCounts: [44])
        try await vm.start()
        await vm.startListening()
        await vm.stopListening()
        #expect(vm.lastError?.contains("Didn't catch any speech") == true)
    }
}

/// Always throws on `respond` — stands in for a broken Ollama. The mapping from
/// HTTP status to `OllamaLLMError` is covered in the Adapters tests; this checks
/// what the session screen does with the result.
struct FailingLLMProvider: LLMProvider {
    let error: Error

    func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error> {
        throw error
    }
}
