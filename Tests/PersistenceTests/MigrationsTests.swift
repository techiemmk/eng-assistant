import Testing
import GRDB
@testable import Persistence

@Suite struct MigrationsTests {
    @Test func v1CreatesAllExpectedColumnsOnSessions() throws {
        let queue = try DatabaseQueue()
        try Migrations.register().migrate(queue)
        try queue.read { conn in
            let cols = try String.fetchAll(conn, sql: "SELECT name FROM pragma_table_info('sessions')")
            for expected in ["id", "scenario_id", "started_at", "ended_at", "mode", "status", "summary", "persona_snapshot"] {
                #expect(cols.contains(expected), "missing column \(expected) in sessions")
            }
        }
    }

    @Test func v1CreatesAllExpectedColumnsOnTurns() throws {
        let queue = try DatabaseQueue()
        try Migrations.register().migrate(queue)
        try queue.read { conn in
            let cols = try String.fetchAll(conn, sql: "SELECT name FROM pragma_table_info('turns')")
            for expected in ["id", "session_id", "turn_index", "speaker", "text", "audio_path", "started_at", "duration_ms", "metrics_json", "is_complete"] {
                #expect(cols.contains(expected), "missing column \(expected) in turns")
            }
        }
    }
}
