import Foundation
import Core
import GRDB

public final class ScenarioRepository {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) {
        self.database = database
    }

    public func create(_ scenario: Scenario) throws {
        let tagsJson = String(data: try encoder.encode(scenario.tags), encoding: .utf8)!
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO scenarios (id, source, title, domain, persona, opening_line,
                                       difficulty, tags_json, notes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                scenario.id,
                scenario.source.rawValue,
                scenario.title,
                scenario.domain.rawValue,
                scenario.persona,
                scenario.openingLine,
                scenario.difficulty,
                tagsJson,
                scenario.notes,
            ])
        }
    }

    public func find(id: String) throws -> Scenario? {
        let decoder = self.decoder
        return try database.queue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM scenarios WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return try Self.scenario(from: row, decoder: decoder)
        }
    }

    public func listCustom() throws -> [Scenario] {
        let decoder = self.decoder
        return try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scenarios WHERE source = 'custom' ORDER BY title")
                .map { try Self.scenario(from: $0, decoder: decoder) }
        }
    }

    public func delete(id: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM scenarios WHERE id = ?", arguments: [id])
        }
    }

    private static func scenario(from row: Row, decoder: JSONDecoder) throws -> Scenario {
        let tagsJson: String = row["tags_json"]
        let tags = (try? decoder.decode([String].self, from: Data(tagsJson.utf8))) ?? []
        let sourceStr: String = row["source"]
        guard let source = ScenarioSource(rawValue: sourceStr) else {
            throw PersistenceDecodingError.malformedField(table: "scenarios", column: "source", value: sourceStr)
        }
        let domainStr: String = row["domain"]
        guard let domain = ScenarioDomain(rawValue: domainStr) else {
            throw PersistenceDecodingError.malformedField(table: "scenarios", column: "domain", value: domainStr)
        }
        return Scenario(
            id: row["id"],
            source: source,
            title: row["title"],
            domain: domain,
            persona: row["persona"],
            openingLine: row["opening_line"],
            difficulty: row["difficulty"],
            tags: tags,
            notes: row["notes"]
        )
    }
}
