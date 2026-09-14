import Foundation

public protocol SessionAnalyzing: Sendable {
    func analyze(sessionId: UUID) async throws -> Debrief
}

public struct SessionAnalyzer: Sendable, SessionAnalyzing {
    private let grammarJudge: GrammarJudge
    private let weakSpotExtractor: WeakSpotExtractor
    private let weakSpotMerger: WeakSpotMerger
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting
    private let scenarioCatalog: ScenarioCatalog
    private let debriefPersister: DebriefPersisting?

    public init(
        grammarJudge: GrammarJudge,
        weakSpotExtractor: WeakSpotExtractor,
        weakSpotMerger: WeakSpotMerger,
        sessionPersister: SessionPersisting,
        turnPersister: TurnPersisting,
        scenarioCatalog: ScenarioCatalog,
        debriefPersister: DebriefPersisting? = nil
    ) {
        self.grammarJudge = grammarJudge
        self.weakSpotExtractor = weakSpotExtractor
        self.weakSpotMerger = weakSpotMerger
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.scenarioCatalog = scenarioCatalog
        self.debriefPersister = debriefPersister
    }

    /// Produces the debrief for a session, computing it at most once.
    ///
    /// The cache is not an optimisation bolted on afterwards — it is what makes
    /// this operation safe to call twice. Analysis merges weak spots, which
    /// *increments* the occurrence count of every pattern it recognises, and the
    /// debrief screen calls this every time it appears. Without the cache,
    /// re-reading an old debrief inflated those counts, and since coach mode
    /// targets the most frequent patterns, simply browsing history changed what
    /// the app coached.
    public func analyze(sessionId: UUID) async throws -> Debrief {
        // `try?` already flattens the optional the persister returns.
        if let cached = try? debriefPersister?.find(sessionId: sessionId) {
            return cached
        }

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
            // The real domain is unknowable here — the scenario is gone and
            // sessions don't record it. Only the debrief's icon and colour read
            // this, so a neutral placeholder is enough.
            domain: .workplace,
            persona: session.personaSnapshot,
            openingLine: "",
            difficulty: 2,
            tags: [],
            notes: nil
        )

        let debrief = CoachingEngine.compose(
            session: session,
            scenario: scenario,
            allTurns: turns,
            sessionMetrics: sessionMetrics,
            newlyCreatedWeakSpots: mergeResult.newlyCreated,
            recurringWeakSpots: mergeResult.recurring
        )

        // Store it only once everything above succeeded, so a failed analysis
        // is retried next time rather than cached as a half-result.
        try? debriefPersister?.save(debrief)
        return debrief
    }
}

public enum SessionAnalyzerError: Error, Equatable {
    case sessionNotFound(UUID)
}
