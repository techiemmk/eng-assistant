import Foundation
import Core
import GRDB

public final class DebriefRepository: DebriefPersisting {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// A debrief that fails to decode — written by an older build with a
    /// different shape — is treated as absent rather than thrown, so the screen
    /// recomputes instead of showing an error the user can do nothing about.
    public func find(sessionId: UUID) throws -> Debrief? {
        let json: String? = try database.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT json FROM debriefs WHERE session_id = ?",
                arguments: [sessionId.uuidString]
            )
        }
        guard let json else { return nil }
        return try? JSONDecoder().decode(Debrief.self, from: Data(json.utf8))
    }

    public func save(_ debrief: Debrief) throws {
        let data = try JSONEncoder().encode(debrief)
        let json = String(decoding: data, as: UTF8.self)
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO debriefs (session_id, json, created_at) VALUES (?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET json = excluded.json,
                                                     created_at = excluded.created_at
                """, arguments: [debrief.session.id.uuidString, json, Date()])
        }
    }

    public func delete(sessionId: UUID) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM debriefs WHERE session_id = ?",
                arguments: [sessionId.uuidString]
            )
        }
    }
}
