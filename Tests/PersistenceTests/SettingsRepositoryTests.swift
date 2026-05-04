import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct SettingsRepositoryTests {
    private static func makeRepo() throws -> SettingsRepository {
        SettingsRepository(database: try Database.inMemory())
    }

    @Test func getMissingReturnsNil() throws {
        let repo = try Self.makeRepo()
        #expect(try repo.get(.defaultMode) == nil)
    }

    @Test func setThenGet() throws {
        let repo = try Self.makeRepo()
        try repo.set(.defaultMode, value: "flow")
        #expect(try repo.get(.defaultMode) == "flow")
    }

    @Test func overwrite() throws {
        let repo = try Self.makeRepo()
        try repo.set(.audioRetentionDays, value: "30")
        try repo.set(.audioRetentionDays, value: "7")
        #expect(try repo.get(.audioRetentionDays) == "7")
    }
}
