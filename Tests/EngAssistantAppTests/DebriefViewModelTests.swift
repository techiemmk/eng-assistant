import Testing
import Foundation
import Core
@testable import EngAssistantApp

@MainActor
@Suite struct DebriefViewModelTests {
    final class StubAnalyzer: SessionAnalyzing, @unchecked Sendable {
        var debrief: Debrief?
        var nextError: Error?
        func analyze(sessionId: UUID) async throws -> Debrief {
            if let e = nextError { throw e }
            return debrief!
        }
    }

    private static func makeDebrief() -> Debrief {
        let session = Session(
            id: UUID(), scenarioId: "x",
            startedAt: Date(), endedAt: Date(),
            mode: .flow, status: .ended,
            summary: nil, personaSnapshot: "p"
        )
        let scenario = Scenario(
            id: "x", source: .builtin, title: "Test", domain: .work,
            persona: "p", openingLine: "Hi.",
            difficulty: 2, tags: [], notes: nil
        )
        let metrics = SessionMetrics(
            userTurnCount: 2, totalWordCount: 30,
            totalFillerCount: 1, totalGrammarIssues: 1,
            averageUniqueWordRatio: 0.9, averageFillerDensity: 0.03
        )
        return Debrief(
            session: session,
            scenario: scenario,
            summary: "Test summary.",
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: [],
            suggestedDrills: []
        )
    }

    @Test func loadingPopulatesDebrief() async throws {
        let analyzer = StubAnalyzer()
        analyzer.debrief = Self.makeDebrief()
        let vm = DebriefViewModel(analyzer: analyzer, sessionId: UUID())
        try await vm.load()
        #expect(vm.debrief != nil)
        #expect(vm.debrief?.summary == "Test summary.")
        #expect(vm.lastError == nil)
    }

    @Test func loadingErrorIsCaptured() async throws {
        let analyzer = StubAnalyzer()
        analyzer.nextError = NSError(domain: "test", code: 1)
        let vm = DebriefViewModel(analyzer: analyzer, sessionId: UUID())
        try? await vm.load()
        #expect(vm.debrief == nil)
        #expect(vm.lastError != nil)
    }
}
