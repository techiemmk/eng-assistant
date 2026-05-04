import Testing
import Foundation
import GRDB
import Core
@testable import Persistence

@Suite struct DecodingErrorTests {
    @Test func sessionWithBadModeThrowsMalformedField() throws {
        let db = try Database.inMemory()
        let id = UUID()
        // Insert a row with an invalid mode value via raw SQL.
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO sessions (id, scenario_id, started_at, mode, status, persona_snapshot)
                VALUES (?, 'work-standup-01', ?, 'NOT_A_MODE', 'active', 'p')
                """, arguments: [id.uuidString, Date()])
        }
        let repo = SessionRepository(database: db)
        #expect(throws: PersistenceDecodingError.self) {
            _ = try repo.find(id: id)
        }
    }
}
