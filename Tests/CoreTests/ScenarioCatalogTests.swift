import Testing
@testable import Core

@Suite struct ScenarioCatalogTests {
    @Test func loadsBundledScenarios() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        #expect(catalog.allScenarios.count >= 6)
    }

    @Test func eachDomainHasAtLeastTwoScenarios() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        for domain in ScenarioDomain.allCases {
            let count = catalog.scenarios(in: domain).count
            #expect(count >= 2, "domain \(domain) has only \(count)")
        }
    }

    @Test func filterByTag() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let meeting = catalog.scenarios(withTag: "meeting")
        #expect(!meeting.isEmpty)
        #expect(meeting.allSatisfy { $0.tags.contains("meeting") })
    }

    @Test func allScenariosHaveBuiltinSource() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        #expect(catalog.allScenarios.allSatisfy { $0.source == .builtin })
    }
}
