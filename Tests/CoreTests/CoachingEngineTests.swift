import Testing
import Foundation
@testable import Core

@Suite struct CoachingEngineTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    private static func makeSession() -> Session {
        Session(
            id: UUID(), scenarioId: "test-01",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: Date(timeIntervalSince1970: 1_777_000_600),
            mode: .flow, status: .ended,
            summary: nil, personaSnapshot: "Test persona."
        )
    }

    @Test func includesSessionAndOneLineSummary() {
        let session = Self.makeSession()
        let metrics = SessionMetrics(
            userTurnCount: 4, totalWordCount: 60,
            totalFillerCount: 5, totalGrammarIssues: 3,
            averageUniqueWordRatio: 0.7, averageFillerDensity: 0.08
        )
        let debrief = CoachingEngine.compose(
            session: session,
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: []
        )
        #expect(debrief.session.id == session.id)
        #expect(!debrief.summary.isEmpty)
        #expect(debrief.sessionMetrics == metrics)
    }

    @Test func summaryReferencesScenarioTitleAndUserTurnCount() {
        let metrics = SessionMetrics(
            userTurnCount: 4, totalWordCount: 60,
            totalFillerCount: 5, totalGrammarIssues: 3,
            averageUniqueWordRatio: 0.7, averageFillerDensity: 0.08
        )
        let debrief = CoachingEngine.compose(
            session: Self.makeSession(),
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: []
        )
        #expect(debrief.summary.contains("Test"))
        #expect(debrief.summary.contains("4"))
    }

    @Test func suggestedDrillsTargetTopRecurringWeakSpots() {
        let now = Date()
        let recurring = [
            WeakSpot(id: UUID(), pattern: "uses 'more better'", category: .grammar,
                     firstSeen: now, lastSeen: now,
                     occurrenceCount: 5, status: .active, exampleTurnIds: []),
            WeakSpot(id: UUID(), pattern: "stutters on conditionals", category: .fluency,
                     firstSeen: now, lastSeen: now,
                     occurrenceCount: 3, status: .active, exampleTurnIds: []),
        ]
        let metrics = SessionMetrics(
            userTurnCount: 1, totalWordCount: 10, totalFillerCount: 0,
            totalGrammarIssues: 0, averageUniqueWordRatio: 1, averageFillerDensity: 0
        )
        let debrief = CoachingEngine.compose(
            session: Self.makeSession(),
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: recurring
        )
        #expect(debrief.suggestedDrills.count == 2)
        #expect(debrief.suggestedDrills[0].contains("more better"))
        #expect(debrief.suggestedDrills[1].contains("conditionals"))
    }

    @Test func splitsNewVsRecurringInOutput() {
        let now = Date()
        let newWS = [WeakSpot(id: UUID(), pattern: "p-new", category: .vocab,
                              firstSeen: now, lastSeen: now,
                              occurrenceCount: 1, status: .active, exampleTurnIds: [])]
        let recurringWS = [WeakSpot(id: UUID(), pattern: "p-old", category: .grammar,
                                    firstSeen: now, lastSeen: now,
                                    occurrenceCount: 3, status: .active, exampleTurnIds: [])]
        let metrics = SessionMetrics(
            userTurnCount: 1, totalWordCount: 5, totalFillerCount: 0,
            totalGrammarIssues: 0, averageUniqueWordRatio: 1, averageFillerDensity: 0
        )
        let debrief = CoachingEngine.compose(
            session: Self.makeSession(),
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: newWS,
            recurringWeakSpots: recurringWS
        )
        #expect(debrief.newlyCreatedWeakSpots.map(\.pattern) == ["p-new"])
        #expect(debrief.recurringWeakSpots.map(\.pattern) == ["p-old"])
    }
}
