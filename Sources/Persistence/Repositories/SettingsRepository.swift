import Foundation
import Core
import GRDB

public final class SettingsRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func get(_ key: AppSettingKey) throws -> String? {
        try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?",
                             arguments: [key.rawValue])
                .map { $0["value"] }
        }
    }

    public func set(_ key: AppSettingKey, value: String) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [key.rawValue, value])
        }
    }
}
