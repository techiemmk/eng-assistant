import Testing
import GRDB
@testable import Persistence

@Suite struct DatabaseTests {
    @Test func inMemoryDatabaseOpens() throws {
        let db = try Database.inMemory()
        try db.queue.read { _ in /* no-op */ }
    }

    @Test func runsMigrationsOnInit() throws {
        let db = try Database.inMemory()
        try db.queue.read { conn in
            let tables = try String.fetchAll(conn, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("sessions"))
            #expect(tables.contains("turns"))
            #expect(tables.contains("scenarios"))
            #expect(tables.contains("weak_spots"))
            #expect(tables.contains("metrics_daily"))
            #expect(tables.contains("settings"))
        }
    }
}
