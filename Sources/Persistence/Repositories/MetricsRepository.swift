import Foundation
import Core
import GRDB

public final class MetricsRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func upsert(_ m: DailyMetrics) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO metrics_daily (date, total_minutes, sessions_count, avg_fluency,
                                           avg_vocab_range, avg_filler_density, avg_grammar_slips_per_min)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    total_minutes = excluded.total_minutes,
                    sessions_count = excluded.sessions_count,
                    avg_fluency = excluded.avg_fluency,
                    avg_vocab_range = excluded.avg_vocab_range,
                    avg_filler_density = excluded.avg_filler_density,
                    avg_grammar_slips_per_min = excluded.avg_grammar_slips_per_min
                """, arguments: [
                m.date, m.totalMinutes, m.sessionsCount, m.avgFluency,
                m.avgVocabRange, m.avgFillerDensity, m.avgGrammarSlipsPerMin,
            ])
        }
    }

    public func find(date: String) throws -> DailyMetrics? {
        try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM metrics_daily WHERE date = ?", arguments: [date])
                .map(Self.daily(from:))
        }
    }

    public func listRecent(days: Int) throws -> [DailyMetrics] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM metrics_daily ORDER BY date DESC LIMIT ?
                """, arguments: [days])
                .map(Self.daily(from:))
        }
    }

    private static func daily(from row: Row) -> DailyMetrics {
        DailyMetrics(
            date: row["date"],
            totalMinutes: row["total_minutes"],
            sessionsCount: row["sessions_count"],
            avgFluency: row["avg_fluency"],
            avgVocabRange: row["avg_vocab_range"],
            avgFillerDensity: row["avg_filler_density"],
            avgGrammarSlipsPerMin: row["avg_grammar_slips_per_min"]
        )
    }
}
