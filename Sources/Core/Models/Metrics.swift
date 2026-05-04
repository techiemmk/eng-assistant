import Foundation

public struct TurnMetrics: Codable, Equatable, Sendable {
    public var wordsPerMinute: Double
    public var pauseRatio: Double          // 0..1
    public var fillerCount: Int
    public var uniqueWordRatio: Double     // unique / total
    public var grammarIssueCount: Int

    public init(
        wordsPerMinute: Double,
        pauseRatio: Double,
        fillerCount: Int,
        uniqueWordRatio: Double,
        grammarIssueCount: Int
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.pauseRatio = pauseRatio
        self.fillerCount = fillerCount
        self.uniqueWordRatio = uniqueWordRatio
        self.grammarIssueCount = grammarIssueCount
    }
}

public struct DailyMetrics: Codable, Equatable, Sendable {
    public let date: String                // ISO yyyy-MM-dd
    public var totalMinutes: Int
    public var sessionsCount: Int
    public var avgFluency: Double
    public var avgVocabRange: Double
    public var avgFillerDensity: Double
    public var avgGrammarSlipsPerMin: Double

    public init(
        date: String,
        totalMinutes: Int,
        sessionsCount: Int,
        avgFluency: Double,
        avgVocabRange: Double,
        avgFillerDensity: Double,
        avgGrammarSlipsPerMin: Double
    ) {
        self.date = date
        self.totalMinutes = totalMinutes
        self.sessionsCount = sessionsCount
        self.avgFluency = avgFluency
        self.avgVocabRange = avgVocabRange
        self.avgFillerDensity = avgFillerDensity
        self.avgGrammarSlipsPerMin = avgGrammarSlipsPerMin
    }
}
