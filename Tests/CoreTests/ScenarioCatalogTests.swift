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


/// Homeopathy is its own practice track, kept disjoint from the clinical one so
/// the two filter chips partition the catalog instead of overlapping.
@Suite struct HomeopathyScenarioTests {
    private static func catalog() throws -> ScenarioCatalog {
        try ScenarioCatalog.loadBuiltIn()
    }

    @Test func homeopathyScenariosExist() throws {
        let scenarios = try Self.catalog().scenarios(withTag: "homeopathy")
        #expect(scenarios.count >= 5, "only \(scenarios.count) homeopathy scenarios")
    }

    @Test func homeopathyScenariosSitInTheWorkDomain() throws {
        let scenarios = try Self.catalog().scenarios(withTag: "homeopathy")
        #expect(scenarios.allSatisfy { $0.domain == .work })
    }

    /// If a scenario carried both track tags it would show under both chips,
    /// which defeats the point of having two.
    @Test func trackTagsDoNotOverlap() throws {
        let catalog = try Self.catalog()
        let medical = Set(catalog.scenarios(withTag: "medical").map(\.id))
        let homeopathy = Set(catalog.scenarios(withTag: "homeopathy").map(\.id))
        #expect(medical.isDisjoint(with: homeopathy))
    }

    @Test func homeopathyScenariosAreFullySpecified() throws {
        for scenario in try Self.catalog().scenarios(withTag: "homeopathy") {
            #expect(!scenario.title.isEmpty)
            #expect(scenario.persona.count > 80, "\(scenario.id) persona is thin")
            #expect(scenario.openingLine.count > 20, "\(scenario.id) opening line is thin")
            #expect((1...5).contains(scenario.difficulty), "\(scenario.id) difficulty out of range")
            #expect(scenario.notes?.isEmpty == false, "\(scenario.id) has no practice note")
        }
    }

    @Test func homeopathyScenariosSpanARangeOfDifficulty() throws {
        let levels = Set(try Self.catalog().scenarios(withTag: "homeopathy").map(\.difficulty))
        #expect(levels.count >= 3, "homeopathy difficulties collapse to \(levels)")
    }

    /// The consultation set should cover more than one kind of conversation —
    /// a first case-taking, a follow-up, and a professional exchange are
    /// different language problems.
    @Test func homeopathyScenariosCoverDistinctConversationTypes() throws {
        let scenarios = try Self.catalog().scenarios(withTag: "homeopathy")
        let secondaryTags = Set(scenarios.flatMap(\.tags)).subtracting(["homeopathy"])
        #expect(secondaryTags.count >= 4, "only \(secondaryTags.count) distinct kinds")
    }
}


/// Case-taking is the core skill of a homeopathic consultation, so the track
/// carries several of them at different levels of difficulty — each one a
/// distinct language problem rather than the same interview again.
@Suite struct HomeopathyCaseTakingTests {
    private static func caseTaking() throws -> [Scenario] {
        try ScenarioCatalog.loadBuiltIn()
            .scenarios(withTag: "homeopathy")
            .filter { $0.tags.contains("case-taking") }
    }

    @Test func severalCaseTakingScenariosExist() throws {
        let scenarios = try Self.caseTaking()
        #expect(scenarios.count >= 6, "only \(scenarios.count) case-taking scenarios")
    }

    /// The point of adding more was to add *harder* ones — a track where
    /// everything sits at one level stops being useful once you've done it.
    @Test func caseTakingReachesTheTopOfTheDifficultyRange() throws {
        let levels = try Self.caseTaking().map(\.difficulty)
        #expect(levels.contains { $0 >= 5 }, "nothing harder than \(levels.max() ?? 0)")
        #expect(Set(levels).count >= 3, "difficulties collapse to \(Set(levels))")
    }

    /// Each scenario should drill a different thing. A shared secondary tag
    /// across all of them would mean they're really one scenario five times.
    @Test func eachCaseTakingScenarioDrillsSomethingDistinct() throws {
        let scenarios = try Self.caseTaking()
        let skills = scenarios.map { Set($0.tags).subtracting(["homeopathy", "case-taking"]) }
        let allSkills = skills.reduce(into: Set<String>()) { $0.formUnion($1) }
        #expect(allSkills.count >= 5, "only \(allSkills.count) distinct skills across \(scenarios.count)")
        for (scenario, skill) in zip(scenarios, skills) {
            #expect(!skill.isEmpty, "\(scenario.id) names no specific skill")
        }
    }

    /// A hard scenario is hard because the persona pushes back in a specific
    /// way, which takes more than a sentence to set up.
    @Test func harderScenariosHaveRicherPersonas() throws {
        for scenario in try Self.caseTaking() where scenario.difficulty >= 4 {
            #expect(
                scenario.persona.count > 200,
                "\(scenario.id) persona is \(scenario.persona.count) chars — too thin for difficulty \(scenario.difficulty)"
            )
            #expect(scenario.notes?.isEmpty == false, "\(scenario.id) has no practice note")
        }
    }

    @Test func caseTakingScenariosOpenInThePatientsVoice() throws {
        for scenario in try Self.caseTaking() {
            #expect(scenario.openingLine.count > 20, "\(scenario.id) opening line is thin")
            // The AI speaks first, so the opening line must not be a stage
            // direction or an instruction to the user.
            #expect(!scenario.openingLine.hasPrefix("You "), "\(scenario.id) opens with an instruction")
        }
    }
}
