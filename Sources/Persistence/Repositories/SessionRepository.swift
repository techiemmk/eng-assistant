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
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try Self.session(from: row)
        }
    }

    public func list(from: Date, to: Date) throws -> [Session] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM sessions
                WHERE started_at >= ? AND started_at < ?
                ORDER BY started_at DESC
                """, arguments: [from, to])
                .map { try Self.session(from: $0) }
        }
    }

    public func findOrphaned() throws -> [Session] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sessions WHERE status = 'active'")
                .map { try Self.session(from: $0) }
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

    private static func session(from row: Row) throws -> Session {
        let idStr: String = row["id"]
        guard let id = UUID(uuidString: idStr) else {
            throw PersistenceDecodingError.malformedField(table: "sessions", column: "id", value: idStr)
        }
        let modeStr: String = row["mode"]
        guard let mode = SessionMode(rawValue: modeStr) else {
            throw PersistenceDecodingError.malformedField(table: "sessions", column: "mode", value: modeStr)
        }
        let statusStr: String = row["status"]
        guard let status = SessionStatus(rawValue: statusStr) else {
            throw PersistenceDecodingError.malformedField(table: "sessions", column: "status", value: statusStr)
        }
        return Session(
            id: id,
            scenarioId: row["scenario_id"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            mode: mode,
            status: status,
            summary: row["summary"],
            personaSnapshot: row["persona_snapshot"]
        )
    }
}
