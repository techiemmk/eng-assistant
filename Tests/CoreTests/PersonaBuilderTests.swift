import Testing
import Foundation
@testable import Core

@Suite struct PersonaBuilderTests {
    private static let scenario = Scenario(
        id: "work-standup-01",
        source: .builtin,
        title: "Standup",
        domain: .workplace,
        persona: "A no-nonsense engineering manager named Priya.",
        openingLine: "Good morning.",
        difficulty: 2,
        tags: ["meeting"],
        notes: nil
    )

    @Test func includesPersonaDescription() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [])
        #expect(prompt.contains("A no-nonsense engineering manager named Priya."))
    }

    @Test func includesDifficultyLevel() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [])
        #expect(prompt.contains("Difficulty: 2"))
    }

    @Test func flowModeOmitsCoachInstructions() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [])
        #expect(!prompt.contains("[[coach:"))
    }

    @Test func coachModeIncludesMarkerInstructions() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        #expect(prompt.contains("[[coach:"))
        #expect(prompt.contains("]]"))
    }

    @Test func flowModeOmitsWeakSpotsBlockEvenWhenProvided() {
        let ws = WeakSpot(
            id: UUID(), pattern: "uses 'more better'",
            category: .grammar, firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 3, status: .active, exampleTurnIds: []
        )
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [ws])
        #expect(!prompt.contains("more better"))
    }

    @Test func coachModeIncludesWeakSpotPatterns() {
        let ws1 = WeakSpot(
            id: UUID(), pattern: "uses 'more better'",
            category: .grammar, firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 3, status: .active, exampleTurnIds: []
        )
        let ws2 = WeakSpot(
            id: UUID(), pattern: "stutters on conditionals",
            category: .fluency, firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 1, status: .active, exampleTurnIds: []
        )
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [ws1, ws2])
        #expect(prompt.contains("uses 'more better'"))
        #expect(prompt.contains("stutters on conditionals"))
    }

    @Test func coachModeWithEmptyWeakSpotsOmitsTheBlockHeader() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        #expect(!prompt.contains("keeps making these mistakes"))
    }
}

/// Coach mode has to ask for two things the parser depends on: a category label
/// on every marker, and the user's wrong wording quoted after "instead of".
@Suite struct PersonaBuilderCoachContractTests {
    private static let scenario = Scenario(
        id: "work-standup-01", source: .builtin, title: "Standup", domain: .workplace,
        persona: "A no-nonsense engineering manager named Priya.",
        openingLine: "Good morning.", difficulty: 2, tags: ["meeting"], notes: nil
    )

    private static func weakSpot(
        _ pattern: String,
        _ category: WeakSpotCategory,
        occurrences: Int = 3
    ) -> WeakSpot {
        WeakSpot(
            id: UUID(), pattern: pattern, category: category,
            firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: occurrences, status: .active, exampleTurnIds: []
        )
    }

    @Test func coachPromptNamesEveryCategoryTheParserAccepts() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        for category in WeakSpotCategory.allCases {
            #expect(prompt.contains(category.rawValue), "prompt should offer '\(category.rawValue)'")
        }
    }

    @Test func coachPromptRequiresGrammarFlagging() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        #expect(prompt.lowercased().contains("grammar"))
        #expect(prompt.contains("Always flag clear grammar mistakes"))
    }

    /// The example has to survive the parser, or the model is being taught a
    /// format the app then throws away.
    @Test func coachPromptExampleParsesIntoAGrammarCorrection() throws {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        let open = try #require(prompt.range(of: "[[coach:grammar:"))
        let close = try #require(prompt.range(of: "]]", range: open.upperBound..<prompt.endIndex))
        let marker = String(prompt[open.lowerBound..<close.upperBound])

        let parsed = CoachMarkerParser.parse(marker)
        let correction = try #require(parsed.corrections.first)
        #expect(correction.category == .grammar)
        #expect(correction.offendingText == "I have finish")
        #expect(parsed.spokenText.isEmpty)
    }

    @Test func coachPromptAsksForTheQuotedWrongWording() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        #expect(prompt.contains("instead of"))
        #expect(prompt.contains("verbatim"))
    }

    @Test func weakSpotBlockCarriesCategoryAndFrequency() {
        let prompt = PersonaBuilder.build(
            scenario: Self.scenario,
            mode: .coach,
            activeWeakSpots: [Self.weakSpot("uses 'more better'", .grammar, occurrences: 7)]
        )
        #expect(prompt.contains("uses 'more better'"))
        #expect(prompt.contains("grammar"))
        #expect(prompt.contains("seen 7x"))
    }

    @Test func weakSpotBlockListsEveryTarget() {
        let spots = [
            Self.weakSpot("uses 'more better'", .grammar),
            Self.weakSpot("says 'actually' constantly", .filler),
            Self.weakSpot("stutters on conditionals", .fluency),
        ]
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: spots)
        for spot in spots {
            #expect(prompt.contains(spot.pattern))
        }
    }

    @Test func flowModeStillOmitsWeakSpotsAndMarkerFormat() {
        let prompt = PersonaBuilder.build(
            scenario: Self.scenario,
            mode: .flow,
            activeWeakSpots: [Self.weakSpot("uses 'more better'", .grammar)]
        )
        #expect(!prompt.contains("more better"))
        #expect(!prompt.contains("Marker format"))
        #expect(prompt.contains("Do not correct the user's English"))
    }
}
