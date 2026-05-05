import Foundation

/// Aggregated per-session metrics. Not persisted as a row of its own — the
/// per-turn `metrics_json` is the source of truth; this is computed for the
/// current debrief and (later) feeds `metrics_daily` rollups.
public struct SessionMetrics: Equatable, Sendable {
    public let userTurnCount: Int
    public let totalWordCount: Int
    public let totalFillerCount: Int
    public let totalGrammarIssues: Int
    public let averageUniqueWordRatio: Double
    public let averageFillerDensity: Double

    public init(
        userTurnCount: Int,
        totalWordCount: Int,
        totalFillerCount: Int,
        totalGrammarIssues: Int,
        averageUniqueWordRatio: Double,
        averageFillerDensity: Double
    ) {
        self.userTurnCount = userTurnCount
        self.totalWordCount = totalWordCount
        self.totalFillerCount = totalFillerCount
        self.totalGrammarIssues = totalGrammarIssues
        self.averageUniqueWordRatio = averageUniqueWordRatio
        self.averageFillerDensity = averageFillerDensity
    }
}

public struct MetricsAnalyzer: Sendable {
    private let grammarJudge: GrammarJudge
    private let turnPersister: TurnPersisting

    public init(grammarJudge: GrammarJudge, turnPersister: TurnPersisting) {
        self.grammarJudge = grammarJudge
        self.turnPersister = turnPersister
    }

    /// Computes per-turn metrics for every complete user turn, persists each one
    /// via `turnPersister.updateMetricsJson`, and returns aggregated session metrics.
    /// Per-turn `GrammarJudge` failures are swallowed (a single LLM hiccup shouldn't
    /// void the rest of the analysis), but persister write errors propagate so a
    /// silent-corruption class of bug can't hide.
    public func analyze(turns: [Turn]) async throws -> SessionMetrics {
        let userTurns = turns.filter { $0.speaker == .user && $0.isComplete }
        var totalWordCount = 0
        var totalFillerCount = 0
        var totalGrammar = 0
        var sumUniqueRatios = 0.0
        var sumFillerDensities = 0.0
        let encoder = JSONEncoder()

        for turn in userTurns {
            let text = TextMetricsCalculator.calculate(text: turn.text)
            let grammarCount = (try? await grammarJudge.countIssues(in: turn.text)) ?? 0
            let metrics = TurnMetrics(
                wordsPerMinute: 0,
                pauseRatio: 0,
                fillerCount: text.fillerCount,
                uniqueWordRatio: text.uniqueWordRatio,
                grammarIssueCount: grammarCount
            )
            let data = try encoder.encode(metrics)
            let json = String(decoding: data, as: UTF8.self)
            try turnPersister.updateMetricsJson(turnId: turn.id, json: json)

            totalWordCount += text.totalWordCount
            totalFillerCount += text.fillerCount
            totalGrammar += grammarCount
            sumUniqueRatios += text.uniqueWordRatio
            sumFillerDensities += text.fillerDensity
        }

        let n = max(userTurns.count, 1)
        return SessionMetrics(
            userTurnCount: userTurns.count,
            totalWordCount: totalWordCount,
            totalFillerCount: totalFillerCount,
            totalGrammarIssues: totalGrammar,
            averageUniqueWordRatio: sumUniqueRatios / Double(n),
            averageFillerDensity: sumFillerDensities / Double(n)
        )
    }
}
