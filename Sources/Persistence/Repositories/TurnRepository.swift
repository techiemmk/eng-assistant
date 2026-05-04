import Foundation
import Core
import GRDB

public final class TurnRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func append(_ turn: Turn) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO turns (id, session_id, turn_index, speaker, text, audio_path,
                                   started_at, duration_ms, metrics_json, is_complete)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                turn.id.uuidString,
                turn.sessionId.uuidString,
                turn.turnIndex,
                turn.speaker.rawValue,
                turn.text,
                turn.audioPath,
                turn.startedAt,
                turn.durationMs,
                turn.metricsJson,
                turn.isComplete,
            ])
        }
    }

    public func list(forSession sessionId: UUID) throws -> [Turn] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM turns WHERE session_id = ? ORDER BY turn_index ASC
                """, arguments: [sessionId.uuidString])
                .map(Self.turn(from:))
        }
    }

    public func listIncomplete(forSession sessionId: UUID) throws -> [Turn] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM turns WHERE session_id = ? AND is_complete = 0 ORDER BY turn_index ASC
                """, arguments: [sessionId.uuidString])
                .map(Self.turn(from:))
        }
    }

    public func markIncomplete(id: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE turns SET is_complete = 0 WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    public func updateMetricsJson(turnId: UUID, json: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE turns SET metrics_json = ? WHERE id = ?",
                           arguments: [json, turnId.uuidString])
        }
    }

    private static func turn(from row: Row) -> Turn {
        Turn(
            id: UUID(uuidString: row["id"])!,
            sessionId: UUID(uuidString: row["session_id"])!,
            turnIndex: row["turn_index"],
            speaker: Speaker(rawValue: row["speaker"])!,
            text: row["text"],
            audioPath: row["audio_path"],
            startedAt: row["started_at"],
            durationMs: row["duration_ms"],
            metricsJson: row["metrics_json"],
            isComplete: row["is_complete"]
        )
    }
}
