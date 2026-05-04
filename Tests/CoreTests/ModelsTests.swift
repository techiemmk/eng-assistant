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

@Suite struct SessionTests {
    @Test func codableRoundTrip() throws {
        let id = UUID()
        let scenarioId = "work-standup-01"
        let started = Date(timeIntervalSince1970: 1_777_000_000)
        let session = Session(
            id: id,
            scenarioId: scenarioId,
            startedAt: started,
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "A no-nonsense engineering manager."
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(session == decoded)
    }

    @Test func modeRawValues() {
        #expect(SessionMode.flow.rawValue == "flow")
        #expect(SessionMode.coach.rawValue == "coach")
    }

    @Test func statusRawValues() {
        #expect(SessionStatus.active.rawValue == "active")
        #expect(SessionStatus.ended.rawValue == "ended")
        #expect(SessionStatus.abandoned.rawValue == "abandoned")
    }
}

@Suite struct TurnTests {
    @Test func codableRoundTrip() throws {
        let turn = Turn(
            id: UUID(),
            sessionId: UUID(),
            turnIndex: 0,
            speaker: .user,
            text: "Hi, I'd like to discuss my Q2 goals.",
            audioPath: "audio/abcd/user-turn-001.wav",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            durationMs: 4200,
            metricsJson: nil,
            isComplete: true
        )
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(Turn.self, from: data)
        #expect(turn == decoded)
    }

    @Test func speakerRawValues() {
        #expect(Speaker.user.rawValue == "user")
        #expect(Speaker.ai.rawValue == "ai")
    }
}
