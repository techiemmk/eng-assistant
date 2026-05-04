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

@Suite struct WeakSpotTests {
    @Test func codableRoundTrip() throws {
        let ws = WeakSpot(
            id: UUID(),
            pattern: "uses 'more better' instead of 'better'",
            category: .grammar,
            firstSeen: Date(timeIntervalSince1970: 1_777_000_000),
            lastSeen: Date(timeIntervalSince1970: 1_777_005_000),
            occurrenceCount: 3,
            status: .active,
            exampleTurnIds: [UUID(), UUID()]
        )
        let data = try JSONEncoder().encode(ws)
        let decoded = try JSONDecoder().decode(WeakSpot.self, from: data)
        #expect(ws == decoded)
    }

    @Test func categoryCases() {
        #expect(WeakSpotCategory.allCases.count == 4)
    }
}

@Suite struct MetricsTests {
    @Test func turnMetricsCodableRoundTrip() throws {
        let m = TurnMetrics(
            wordsPerMinute: 132.5,
            pauseRatio: 0.18,
            fillerCount: 4,
            uniqueWordRatio: 0.72,
            grammarIssueCount: 1
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(TurnMetrics.self, from: data)
        #expect(m == decoded)
    }

    @Test func dailyMetricsCodableRoundTrip() throws {
        let m = DailyMetrics(
            date: "2026-05-04",
            totalMinutes: 22,
            sessionsCount: 2,
            avgFluency: 130.0,
            avgVocabRange: 0.7,
            avgFillerDensity: 0.05,
            avgGrammarSlipsPerMin: 0.5
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(DailyMetrics.self, from: data)
        #expect(m == decoded)
    }
}

@Suite struct AppSettingsKeyTests {
    @Test func knownKeysPresent() {
        #expect(AppSettingKey.defaultMode.rawValue == "default_mode")
        #expect(AppSettingKey.audioRetentionDays.rawValue == "audio_retention_days")
        #expect(AppSettingKey.vadSensitivity.rawValue == "vad_sensitivity")
        #expect(AppSettingKey.llmModelName.rawValue == "llm_model_name")
        #expect(AppSettingKey.ttsVoiceName.rawValue == "tts_voice_name")
    }
}
