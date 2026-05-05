import Foundation

public struct SessionAnalyzer: Sendable {
    private let grammarJudge: GrammarJudge
    private let weakSpotExtractor: WeakSpotExtractor
    private let weakSpotMerger: WeakSpotMerger
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting
    private let scenarioCatalog: ScenarioCatalog

    public init(
        grammarJudge: GrammarJudge,
        weakSpotExtractor: WeakSpotExtractor,
        weakSpotMerger: WeakSpotMerger,
        sessionPersister: SessionPersisting,
        turnPersister: TurnPersisting,
        scenarioCatalog: ScenarioCatalog
    ) {
        self.grammarJudge = grammarJudge
        self.weakSpotExtractor = weakSpotExtractor
        self.weakSpotMerger = weakSpotMerger
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.scenarioCatalog = scenarioCatalog
    }

    public func analyze(sessionId: UUID) async throws -> Debrief {
        guard let session = try sessionPersister.find(id: sessionId) else {
            throw SessionAnalyzerError.sessionNotFound(sessionId)
        }
        let turns = try turnPersister.list(forSession: sessionId)

        let metricsAnalyzer = MetricsAnalyzer(grammarJudge: grammarJudge, turnPersister: turnPersister)
        let sessionMetrics = try await metricsAnalyzer.analyze(turns: turns)

        let userTranscript = turns
            .filter { $0.speaker == .user && $0.isComplete }
            .map(\.text)
            .joined(separator: "\n")
        let candidates = try await weakSpotExtractor.extract(fromUserTranscript: userTranscript)
        let userTurnIds = turns.filter { $0.speaker == .user }.map(\.id)
        let mergeResult = try weakSpotMerger.merge(
            candidates: candidates,
            sessionUserTurnIds: userTurnIds,
            now: Date()
        )

        // Resolve scenario: try the catalog first (for built-ins), fall back to
        // a synthetic scenario reconstructed from the session's personaSnapshot.
        let scenario = scenarioCatalog.scenario(id: session.scenarioId) ?? Scenario(
            id: session.scenarioId,
            source: .custom,
            title: session.scenarioId,
            domain: .work,
            persona: session.personaSnapshot,
            openingLine: "",
            difficulty: 2,
            tags: [],
            notes: nil
        )

        return CoachingEngine.compose(
            session: session,
            scenario: scenario,
            allTurns: turns,
            sessionMetrics: sessionMetrics,
            newlyCreatedWeakSpots: mergeResult.newlyCreated,
            recurringWeakSpots: mergeResult.recurring
        )
    }
}

public enum SessionAnalyzerError: Error, Equatable {
    case sessionNotFound(UUID)
}
