import Testing
import Foundation
@testable import Core

@Suite struct ScenarioTests {
    @Test func codableRoundTrip() throws {
        let original = Scenario(
            id: "work-standup-01",
            source: .builtin,
            title: "Daily Standup",
            domain: .work,
            persona: "A no-nonsense engineering manager.",
            openingLine: "Good morning, what did you finish yesterday?",
            difficulty: 2,
            tags: ["meeting", "team"],
            notes: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Scenario.self, from: data)
        #expect(original == decoded)
    }

    @Test func domainCases() {
        #expect(ScenarioDomain.allCases.count == 3)
        #expect(ScenarioDomain.allCases.contains(.work))
        #expect(ScenarioDomain.allCases.contains(.networking))
        #expect(ScenarioDomain.allCases.contains(.social))
    }
}
