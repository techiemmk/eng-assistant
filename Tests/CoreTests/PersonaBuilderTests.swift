import Testing
import Foundation
@testable import Core

@Suite struct PersonaBuilderTests {
    private static let scenario = Scenario(
        id: "work-standup-01",
        source: .builtin,
        title: "Standup",
        domain: .work,
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
        #expect(!prompt.contains("recurring user mistakes"))
    }
}
