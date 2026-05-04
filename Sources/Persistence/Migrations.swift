import Foundation
import GRDB

public enum Migrations {
    public static func register() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "scenarios") { t in
                t.column("id", .text).primaryKey()
                t.column("source", .text).notNull()
                t.column("title", .text).notNull()
                t.column("domain", .text).notNull()
                t.column("persona", .text).notNull()
                t.column("opening_line", .text).notNull()
                t.column("difficulty", .integer).notNull()
                t.column("tags_json", .text).notNull()    // JSON array
                t.column("notes", .text)
            }

            try db.create(table: "sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("scenario_id", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("mode", .text).notNull()
                t.column("status", .text).notNull()
                t.column("summary", .text)
                t.column("persona_snapshot", .text).notNull()
            }
            try db.create(index: "idx_sessions_started_at", on: "sessions", columns: ["started_at"])
            try db.create(index: "idx_sessions_status", on: "sessions", columns: ["status"])

            try db.create(table: "turns") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("turn_index", .integer).notNull()
                t.column("speaker", .text).notNull()
                t.column("text", .text).notNull()
                t.column("audio_path", .text)
                t.column("started_at", .datetime).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("metrics_json", .text)
                t.column("is_complete", .boolean).notNull().defaults(to: true)
            }
            try db.create(index: "idx_turns_session", on: "turns", columns: ["session_id", "turn_index"])

            try db.create(table: "weak_spots") { t in
                t.column("id", .text).primaryKey()
                t.column("pattern", .text).notNull()
                t.column("category", .text).notNull()
                t.column("first_seen", .datetime).notNull()
                t.column("last_seen", .datetime).notNull()
                t.column("occurrence_count", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("example_turn_ids_json", .text).notNull()
            }
            try db.create(index: "idx_weak_spots_status_count",
                          on: "weak_spots",
                          columns: ["status", "occurrence_count"])

            try db.create(table: "metrics_daily") { t in
                t.column("date", .text).primaryKey()
                t.column("total_minutes", .integer).notNull()
                t.column("sessions_count", .integer).notNull()
                t.column("avg_fluency", .double).notNull()
                t.column("avg_vocab_range", .double).notNull()
                t.column("avg_filler_density", .double).notNull()
                t.column("avg_grammar_slips_per_min", .double).notNull()
            }

            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        return migrator
    }
}
