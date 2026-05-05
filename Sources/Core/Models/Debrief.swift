import Foundation

public struct Debrief: Equatable, Sendable {
    public let session: Session
    public let scenario: Scenario
    public let summary: String
    public let allTurns: [Turn]
    public let sessionMetrics: SessionMetrics
    public let newlyCreatedWeakSpots: [WeakSpot]
    public let recurringWeakSpots: [WeakSpot]
    public let suggestedDrills: [String]

    public init(
        session: Session,
        scenario: Scenario,
        summary: String,
        allTurns: [Turn],
        sessionMetrics: SessionMetrics,
        newlyCreatedWeakSpots: [WeakSpot],
        recurringWeakSpots: [WeakSpot],
        suggestedDrills: [String]
    ) {
        self.session = session
        self.scenario = scenario
        self.summary = summary
        self.allTurns = allTurns
        self.sessionMetrics = sessionMetrics
        self.newlyCreatedWeakSpots = newlyCreatedWeakSpots
        self.recurringWeakSpots = recurringWeakSpots
        self.suggestedDrills = suggestedDrills
    }
}
