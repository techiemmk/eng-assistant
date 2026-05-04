import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct MetricsRepositoryTests {
    private static func makeRepo() throws -> MetricsRepository {
        MetricsRepository(database: try Database.inMemory())
    }

    private static func sample(date: String, sessions: Int = 1, fluency: Double = 130) -> DailyMetrics {
        DailyMetrics(
            date: date,
            totalMinutes: 20,
            sessionsCount: sessions,
            avgFluency: fluency,
            avgVocabRange: 0.7,
            avgFillerDensity: 0.05,
            avgGrammarSlipsPerMin: 0.5
        )
    }

    @Test func upsertCreatesAndReplaces() throws {
        let repo = try Self.makeRepo()
        try repo.upsert(Self.sample(date: "2026-05-04", fluency: 130))
        try repo.upsert(Self.sample(date: "2026-05-04", fluency: 140))
        let fetched = try repo.find(date: "2026-05-04")
        #expect(fetched?.avgFluency == 140)
    }

    @Test func listRecentOrderedDesc() throws {
        let repo = try Self.makeRepo()
        try repo.upsert(Self.sample(date: "2026-05-01"))
        try repo.upsert(Self.sample(date: "2026-05-04"))
        try repo.upsert(Self.sample(date: "2026-05-02"))
        let recent = try repo.listRecent(days: 30)
        #expect(recent.map(\.date) == ["2026-05-04", "2026-05-02", "2026-05-01"])
    }
}
