import Foundation
import Core
import GRDB

public final class SessionRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func create(_ session: Session) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (id, scenario_id, started_at, ended_at, mode, status, summary, persona_snapshot)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                session.id.uuidString,
                session.scenarioId,
                session.startedAt,
                session.endedAt,
                session.mode.rawValue,
                session.status.rawValue,
                session.summary,
                session.personaSnapshot,
            ])
        }
    }

    public func find(id: UUID) throws -> Session? {
        try database.queue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [id.uuidString])
            return row.map(Self.session(from:))
        }
    }

    public func list(from: Date, to: Date) throws -> [Session] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM sessions
                WHERE started_at >= ? AND started_at < ?
                ORDER BY started_at DESC
                """, arguments: [from, to])
                .map(Self.session(from:))
        }
    }

    public func findOrphaned() throws -> [Session] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sessions WHERE status = 'active'")
                .map(Self.session(from:))
        }
    }

    public func finalize(id: UUID, endedAt: Date, summary: String?) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                UPDATE sessions SET ended_at = ?, status = 'ended', summary = ? WHERE id = ?
                """, arguments: [endedAt, summary, id.uuidString])
        }
    }

    public func markAbandoned(id: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE sessions SET status = 'abandoned' WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    private static func session(from row: Row) -> Session {
        Session(
            id: UUID(uuidString: row["id"])!,
            scenarioId: row["scenario_id"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            mode: SessionMode(rawValue: row["mode"])!,
            status: SessionStatus(rawValue: row["status"])!,
            summary: row["summary"],
            personaSnapshot: row["persona_snapshot"]
        )
    }
}
