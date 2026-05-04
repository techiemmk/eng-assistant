import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct ScenarioRepositoryTests {
    private static func makeRepo() throws -> ScenarioRepository {
        ScenarioRepository(database: try Database.inMemory())
    }

    private static func makeCustom(id: String = "custom-1") -> Scenario {
        Scenario(
            id: id,
            source: .custom,
            title: "Manager 1:1 Tomorrow",
            domain: .work,
            persona: "My new manager Priya, friendly but skeptical.",
            openingLine: "So, how's it been going?",
            difficulty: 3,
            tags: ["1on1", "manager"],
            notes: "Q2 goals discussion."
        )
    }

    @Test func createAndFind() throws {
        let repo = try Self.makeRepo()
        let s = Self.makeCustom()
        try repo.create(s)
        let found = try repo.find(id: s.id)
        #expect(found == s)
    }

    @Test func listAllCustomOnly() throws {
        let repo = try Self.makeRepo()
        try repo.create(Self.makeCustom(id: "custom-a"))
        try repo.create(Self.makeCustom(id: "custom-b"))
        let all = try repo.listCustom()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.source == .custom })
    }

    @Test func deleteRemovesIt() throws {
        let repo = try Self.makeRepo()
        let s = Self.makeCustom()
        try repo.create(s)
        try repo.delete(id: s.id)
        #expect(try repo.find(id: s.id) == nil)
    }
}
