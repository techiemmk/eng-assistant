import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct MetricsAnalyzerTests {
    private static func makeUserTurn(_ text: String, sessionId: UUID, index: Int) -> Turn {
        Turn(
            id: UUID(), sessionId: sessionId, turnIndex: index, speaker: .user,
            text: text, audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        )
    }

    private static func makeAITurn(_ text: String, sessionId: UUID, index: Int) -> Turn {
        Turn(
            id: UUID(), sessionId: sessionId, turnIndex: index, speaker: .ai,
            text: text, audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        )
    }

    final class CapturingPersister: TurnPersisting, @unchecked Sendable {
        var stored: [(turnId: UUID, json: String)] = []
        func append(_ turn: Turn) throws {}
        func list(forSession sessionId: UUID) throws -> [Turn] { [] }
        func markIncomplete(id: UUID) throws {}
        func updateMetricsJson(turnId: UUID, json: String) throws {
            stored.append((turnId, json))
        }
    }

    @Test func computesTurnMetricsForEachUserTurnAndPersistsThem() async throws {
        let sessionId = UUID()
        let turns: [Turn] = [
            Self.makeAITurn("Good morning.", sessionId: sessionId, index: 0),
            Self.makeUserTurn("Um, yesterday I have finish the auth refactor.", sessionId: sessionId, index: 1),
            Self.makeAITurn("Great.", sessionId: sessionId, index: 2),
            Self.makeUserTurn("You know, I think it goes well.", sessionId: sessionId, index: 3),
        ]
        let llm = FakeLLMProvider(scriptedReplyBatches: [
            ["{\"grammarIssueCount\": 2}"],     // for user turn 1
            ["{\"grammarIssueCount\": 1}"],     // for user turn 3
        ])
        let persister = CapturingPersister()
        let analyzer = MetricsAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            turnPersister: persister
        )
        let session = try await analyzer.analyze(turns: turns)
        #expect(persister.stored.count == 2)
        #expect(session.userTurnCount == 2)
        #expect(session.totalGrammarIssues == 3)
        #expect(session.totalFillerCount > 0)  // "um", "you know"
        #expect(session.averageUniqueWordRatio > 0)
    }

    @Test func emptyTranscriptProducesZeroSessionMetrics() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": 0}"])
        let persister = CapturingPersister()
        let analyzer = MetricsAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            turnPersister: persister
        )
        let session = try await analyzer.analyze(turns: [])
        #expect(session.userTurnCount == 0)
        #expect(session.totalGrammarIssues == 0)
        #expect(session.totalFillerCount == 0)
        #expect(persister.stored.isEmpty)
    }

    @Test func skipsAITurnsAndIncompleteUserTurns() async throws {
        let sessionId = UUID()
        var incomplete = Self.makeUserTurn("oh no", sessionId: sessionId, index: 1)
        incomplete.isComplete = false
        let turns: [Turn] = [
            Self.makeAITurn("hi", sessionId: sessionId, index: 0),
            incomplete,
            Self.makeUserTurn("I am ready.", sessionId: sessionId, index: 2),
        ]
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": 0}"])
        let persister = CapturingPersister()
        let analyzer = MetricsAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            turnPersister: persister
        )
        let session = try await analyzer.analyze(turns: turns)
        #expect(session.userTurnCount == 1)
        #expect(persister.stored.count == 1)
    }
}
