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

/// The medical scenarios are a practice track inside the work domain, reachable
/// by tag rather than by a domain of their own.
@Suite struct MedicalScenarioTests {
    private static func catalog() throws -> ScenarioCatalog {
        try ScenarioCatalog.loadBuiltIn()
    }

    @Test func medicalScenariosExist() throws {
        let medical = try Self.catalog().scenarios(withTag: "medical")
        #expect(medical.count >= 5, "only \(medical.count) medical scenarios")
    }

    @Test func medicalScenariosSitInTheWorkDomain() throws {
        let medical = try Self.catalog().scenarios(withTag: "medical")
        #expect(medical.allSatisfy { $0.domain == .work })
    }

    /// A scenario is only usable if the persona and opening line are both
    /// substantial enough for the model to stay in character.
    @Test func medicalScenariosAreFullySpecified() throws {
        for scenario in try Self.catalog().scenarios(withTag: "medical") {
            #expect(!scenario.title.isEmpty)
            #expect(scenario.persona.count > 80, "\(scenario.id) persona is thin")
            #expect(scenario.openingLine.count > 20, "\(scenario.id) opening line is thin")
            #expect((1...5).contains(scenario.difficulty), "\(scenario.id) difficulty out of range")
        }
    }

    /// They should span a range, not all sit at the same level — a clinician
    /// practising history-taking isn't doing the same difficulty as an MDT.
    @Test func medicalScenariosSpanARangeOfDifficulty() throws {
        let levels = Set(try Self.catalog().scenarios(withTag: "medical").map(\.difficulty))
        #expect(levels.count >= 3, "medical difficulties collapse to \(levels)")
    }

    @Test func everyScenarioIdIsUnique() throws {
        let ids = try Self.catalog().allScenarios.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// The non-medical work scenarios must still be reachable — the clinical
    /// track was added alongside them, not over them.
    @Test func officeWorkScenariosStillPresent() throws {
        let work = try Self.catalog().scenarios(in: .work)
        let office = work.filter { !$0.tags.contains("medical") }
        #expect(office.count >= 2)
    }
}
