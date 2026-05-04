import Foundation
import Core
import GRDB

public final class WeakSpotRepository {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) {
        self.database = database
    }

    public func create(_ ws: WeakSpot) throws {
        let json = String(data: try encoder.encode(ws.exampleTurnIds.map { $0.uuidString }),
                          encoding: .utf8)!
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO weak_spots (id, pattern, category, first_seen, last_seen,
                                        occurrence_count, status, example_turn_ids_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                ws.id.uuidString,
                ws.pattern,
                ws.category.rawValue,
                ws.firstSeen,
                ws.lastSeen,
                ws.occurrenceCount,
                ws.status.rawValue,
                json,
            ])
        }
    }

    public func findByPattern(_ pattern: String) throws -> WeakSpot? {
        let decoder = self.decoder
        return try database.queue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM weak_spots WHERE pattern = ?",
                                             arguments: [pattern]) else {
                return nil
            }
            return Self.weakSpot(from: row, decoder: decoder)
        }
    }

    public func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
        let decoder = self.decoder
        let encoder = self.encoder
        try database.queue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM weak_spots WHERE id = ?",
                                             arguments: [id.uuidString]) else {
                throw WeakSpotRepositoryError.notFound(id)
            }
            let existing = Self.weakSpot(from: row, decoder: decoder)
            var ids = existing.exampleTurnIds
            if let newId = addExampleTurnId, !ids.contains(newId) {
                ids.append(newId)
            }
            let json = String(data: try encoder.encode(ids.map { $0.uuidString }), encoding: .utf8)!
            try db.execute(sql: """
                UPDATE weak_spots SET occurrence_count = occurrence_count + 1,
                                      last_seen = ?,
                                      example_turn_ids_json = ?
                WHERE id = ?
                """, arguments: [lastSeen, json, id.uuidString])
        }
    }

    public func listActiveByFrequency(limit: Int) throws -> [WeakSpot] {
        let decoder = self.decoder
        return try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM weak_spots WHERE status = 'active'
                ORDER BY occurrence_count DESC, last_seen DESC
                LIMIT ?
                """, arguments: [limit])
                .map { Self.weakSpot(from: $0, decoder: decoder) }
        }
    }

    public func markResolved(id: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE weak_spots SET status = 'resolved' WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    private static func weakSpot(from row: Row, decoder: JSONDecoder) -> WeakSpot {
        let json: String = row["example_turn_ids_json"]
        let stringIds = (try? decoder.decode([String].self, from: Data(json.utf8))) ?? []
        let ids = stringIds.compactMap { UUID(uuidString: $0) }
        return WeakSpot(
            id: UUID(uuidString: row["id"])!,
            pattern: row["pattern"],
            category: WeakSpotCategory(rawValue: row["category"])!,
            firstSeen: row["first_seen"],
            lastSeen: row["last_seen"],
            occurrenceCount: row["occurrence_count"],
            status: WeakSpotStatus(rawValue: row["status"])!,
            exampleTurnIds: ids
        )
    }
}

public enum WeakSpotRepositoryError: Error, Equatable {
    case notFound(UUID)
}
