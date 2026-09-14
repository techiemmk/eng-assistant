import Testing
import Foundation
import Core
import Fakes

/// Analysis merges weak spots, which *increments* the occurrence count of every
/// pattern it recognises — and the debrief screen ran it every time it
/// appeared. Re-reading an old debrief therefore inflated those counts, and
/// coach mode targets the most frequent patterns, so browsing history quietly
/// steered the coaching. These pin the fix.
@Suite struct DebriefIdempotenceTests {
    final class InMemoryDebriefPersister: DebriefPersisting, @unchecked Sendable {
        var stored: [UUID: Debrief] = [:]
        var saveCount = 0
        func find(sessionId: UUID) throws -> Debrief? { stored[sessionId] }
        func save(_ debrief: Debrief) throws {
            saveCount += 1
            stored[debrief.session.id] = debrief
        }
        func delete(sessionId: UUID) throws { stored[sessionId] = nil }
    }

    final class CountingWeakSpotPersister: WeakSpotPersisting, @unchecked Sendable {
        var store: [UUID: WeakSpot] = [:]
        var incrementCount = 0
        func listActiveByFrequency(limit: Int) throws -> [WeakSpot] {
            Array(store.values.filter { $0.status == .active }
                .sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(limit))
        }
        func create(_ weakSpot: WeakSpot) throws { store[weakSpot.id] = weakSpot }
        func findByPattern(_ pattern: String) throws -> WeakSpot? {
            store.values.first { $0.pattern == pattern }
        }
        func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
            incrementCount += 1
            store[id]?.occurrenceCount += 1
            store[id]?.lastSeen = lastSeen
        }
        func markResolved(id: UUID) throws { store[id]?.status = .resolved }
    }

    private static let scenario = Scenario(
        id: "idem-01", source: .builtin, title: "Idempotence", domain: .workplace,
        persona: "p", openingLine: "hi", difficulty: 2, tags: [], notes: nil
    )

    /// Builds an analyzer over a session with one user turn, scripting the LLM
    /// so the same weak-spot pattern is always extracted.
    private static func makeAnalyzer(
        debriefPersister: InMemoryDebriefPersister?,
        weakSpots: CountingWeakSpotPersister
    ) throws -> (SessionAnalyzer, UUID, InMemorySessionPersister, InMemoryTurnPersister) {
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let sessionId = UUID()
        try sessions.create(Session(
            id: sessionId, scenarioId: scenario.id, startedAt: Date(), endedAt: Date(),
            mode: .flow, status: .ended, summary: "done", personaSnapshot: "p"
        ))
        try turns.append(Turn(
            id: UUID(), sessionId: sessionId, turnIndex: 0, speaker: .user,
            text: "Yesterday I have finish the work.", audioPath: nil,
            startedAt: Date(), durationMs: 0, metricsJson: nil, isComplete: true
        ))

        // Enough scripted replies for several analyses: one grammar-judge call
        // per user turn, plus one weak-spot extraction.
        let batches = Array(repeating: [#"{"grammarIssueCount": 1}"#], count: 6)
            + Array(repeating: [#"{"patterns":[{"pattern":"uses 'have finish'","category":"grammar"}]}"#], count: 6)
        let llm = FakeLLMProvider(scriptedReplyBatches: interleave(batches))
        let options = LLMOptions(modelName: "fake")

        let analyzer = SessionAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: options),
            weakSpotExtractor: WeakSpotExtractor(llm: llm, options: options),
            weakSpotMerger: WeakSpotMerger(persister: weakSpots),
            sessionPersister: sessions,
            turnPersister: turns,
            scenarioCatalog: ScenarioCatalog(allScenarios: [scenario]),
            debriefPersister: debriefPersister
        )
        return (analyzer, sessionId, sessions, turns)
    }

    /// One grammar call then one extraction call, repeated.
    private static func interleave(_ batches: [[String]]) -> [[String]] {
        let half = batches.count / 2
        return (0..<half).flatMap { [batches[$0], batches[half + $0]] }
    }

    @Test func firstAnalysisCreatesTheWeakSpot() async throws {
        let weakSpots = CountingWeakSpotPersister()
        let cache = InMemoryDebriefPersister()
        let (analyzer, sessionId, _, _) = try Self.makeAnalyzer(
            debriefPersister: cache, weakSpots: weakSpots
        )

        let debrief = try await analyzer.analyze(sessionId: sessionId)

        #expect(debrief.newlyCreatedWeakSpots.count == 1)
        #expect(weakSpots.store.count == 1)
        #expect(weakSpots.incrementCount == 0, "a brand new pattern isn't an increment")
        #expect(cache.saveCount == 1)
    }

    /// The regression this whole change exists for.
    @Test func reanalysingDoesNotIncrementOccurrenceCounts() async throws {
        let weakSpots = CountingWeakSpotPersister()
        let cache = InMemoryDebriefPersister()
        let (analyzer, sessionId, _, _) = try Self.makeAnalyzer(
            debriefPersister: cache, weakSpots: weakSpots
        )

        _ = try await analyzer.analyze(sessionId: sessionId)
        let countAfterFirst = weakSpots.store.values.first?.occurrenceCount

        // Three more visits to the same debrief.
        for _ in 0..<3 { _ = try await analyzer.analyze(sessionId: sessionId) }

        #expect(weakSpots.incrementCount == 0, "revisiting a debrief incremented \(weakSpots.incrementCount) times")
        #expect(weakSpots.store.values.first?.occurrenceCount == countAfterFirst)
        #expect(weakSpots.store.count == 1, "revisiting created duplicate weak spots")
    }

    @Test func reanalysingReturnsTheSameDebriefWithoutRecomputing() async throws {
        let weakSpots = CountingWeakSpotPersister()
        let cache = InMemoryDebriefPersister()
        let (analyzer, sessionId, _, _) = try Self.makeAnalyzer(
            debriefPersister: cache, weakSpots: weakSpots
        )

        let first = try await analyzer.analyze(sessionId: sessionId)
        let second = try await analyzer.analyze(sessionId: sessionId)

        #expect(first == second)
        // Saved once, not once per visit — so the LLM wasn't called again
        // either; the scripted provider would have been exhausted otherwise.
        #expect(cache.saveCount == 1)
    }

    /// Without a cache the old behaviour is still there, which is the proof
    /// that the cache — not some incidental change — is what fixed it.
    @Test func withoutACacheRepeatedAnalysisStillInflates() async throws {
        let weakSpots = CountingWeakSpotPersister()
        let (analyzer, sessionId, _, _) = try Self.makeAnalyzer(
            debriefPersister: nil, weakSpots: weakSpots
        )

        _ = try await analyzer.analyze(sessionId: sessionId)
        _ = try await analyzer.analyze(sessionId: sessionId)

        #expect(weakSpots.incrementCount == 1)
        #expect(weakSpots.store.values.first?.occurrenceCount == 2)
    }

    /// A failed analysis must not be cached as a half-result, or the error
    /// would become permanent.
    @Test func aFailedAnalysisIsNotCached() async throws {
        let weakSpots = CountingWeakSpotPersister()
        let cache = InMemoryDebriefPersister()
        let sessions = InMemorySessionPersister()
        let turns = InMemoryTurnPersister()
        let missingId = UUID()

        let llm = FakeLLMProvider(scriptedReplies: ["{}"])
        let options = LLMOptions(modelName: "fake")
        let analyzer = SessionAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: options),
            weakSpotExtractor: WeakSpotExtractor(llm: llm, options: options),
            weakSpotMerger: WeakSpotMerger(persister: weakSpots),
            sessionPersister: sessions,
            turnPersister: turns,
            scenarioCatalog: ScenarioCatalog(allScenarios: [Self.scenario]),
            debriefPersister: cache
        )

        await #expect(throws: SessionAnalyzerError.sessionNotFound(missingId)) {
            _ = try await analyzer.analyze(sessionId: missingId)
        }
        #expect(cache.saveCount == 0)
        #expect(try cache.find(sessionId: missingId) == nil)
    }
}
