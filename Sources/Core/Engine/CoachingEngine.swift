import Foundation

public enum CoachingEngine {
    public static func compose(
        session: Session,
        scenario: Scenario,
        allTurns: [Turn],
        sessionMetrics: SessionMetrics,
        newlyCreatedWeakSpots: [WeakSpot],
        recurringWeakSpots: [WeakSpot]
    ) -> Debrief {
        let summary = makeSummary(scenario: scenario, metrics: sessionMetrics)
        let drills = makeDrills(recurringWeakSpots: recurringWeakSpots,
                                newlyCreatedWeakSpots: newlyCreatedWeakSpots)
        return Debrief(
            session: session,
            scenario: scenario,
            summary: summary,
            allTurns: allTurns,
            sessionMetrics: sessionMetrics,
            newlyCreatedWeakSpots: newlyCreatedWeakSpots,
            recurringWeakSpots: recurringWeakSpots,
            suggestedDrills: drills
        )
    }

    private static func makeSummary(scenario: Scenario, metrics: SessionMetrics) -> String {
        let n = metrics.userTurnCount
        let issues = metrics.totalGrammarIssues
        return "Practiced '\(scenario.title)' across \(n) user turn\(n == 1 ? "" : "s"); \(issues) clear grammar slip\(issues == 1 ? "" : "s") flagged."
    }

    private static func makeDrills(recurringWeakSpots: [WeakSpot], newlyCreatedWeakSpots: [WeakSpot]) -> [String] {
        let top = recurringWeakSpots
            .sorted { $0.occurrenceCount > $1.occurrenceCount }
            .prefix(3)
        return top.map { "Drill: \($0.pattern)" }
    }
}
