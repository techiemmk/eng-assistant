import Testing
import Foundation
import Core
@testable import EngAssistantApp

/// Covers the two things the debrief screen gained: retiring a weak spot, and
/// playing a turn's recording back.
@MainActor
@Suite struct DebriefActionsTests {
    final class StubAnalyzer: SessionAnalyzing, @unchecked Sendable {
        var debrief: Debrief
        var error: Error?
        var callCount = 0
        init(debrief: Debrief) { self.debrief = debrief }
        func analyze(sessionId: UUID) async throws -> Debrief {
            callCount += 1
            if let error { throw error }
            return debrief
        }
    }

    final class WeakSpotStore: WeakSpotPersisting, @unchecked Sendable {
        var store: [UUID: WeakSpot] = [:]
        var resolveError: Error?
        var resolved: [UUID] = []
        func listActiveByFrequency(limit: Int) throws -> [WeakSpot] {
            Array(store.values.filter { $0.status == .active }.prefix(limit))
        }
        func create(_ weakSpot: WeakSpot) throws { store[weakSpot.id] = weakSpot }
        func findByPattern(_ pattern: String) throws -> WeakSpot? {
            store.values.first { $0.pattern == pattern }
        }
        func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {}
        func markResolved(id: UUID) throws {
            if let resolveError { throw resolveError }
            resolved.append(id)
            store[id]?.status = .resolved
        }
    }

    final class RecordingPlayback: AudioPlayback, @unchecked Sendable {
        var played: [Int] = []
        var error: Error?
        func play(_ audio: SynthesizedAudio) async throws {
            if let error { throw error }
            played.append(audio.data.count)
        }
    }

    struct Boom: Error {}

    private static func weakSpot(_ pattern: String, status: WeakSpotStatus = .active) -> WeakSpot {
        WeakSpot(id: UUID(), pattern: pattern, category: .grammar,
                 firstSeen: Date(), lastSeen: Date(), occurrenceCount: 3,
                 status: status, exampleTurnIds: [])
    }

    private static func debrief(turns: [Turn] = [], weakSpots: [WeakSpot] = []) -> Debrief {
        let sessionId = UUID()
        return Debrief(
            session: Session(id: sessionId, scenarioId: "s", startedAt: Date(), endedAt: Date(),
                             mode: .flow, status: .ended, summary: "s", personaSnapshot: "p"),
            scenario: Scenario(id: "s", source: .builtin, title: "S", domain: .workplace,
                               persona: "p", openingLine: "hi", difficulty: 2, tags: [], notes: nil),
            summary: "summary",
            allTurns: turns,
            sessionMetrics: SessionMetrics(userTurnCount: 1, totalWordCount: 5,
                                           totalFillerCount: 0, totalGrammarIssues: 0,
                                           averageUniqueWordRatio: 1, averageFillerDensity: 0),
            newlyCreatedWeakSpots: weakSpots,
            recurringWeakSpots: [],
            suggestedDrills: []
        )
    }

    private static func turn(audioPath: String?) -> Turn {
        Turn(id: UUID(), sessionId: UUID(), turnIndex: 0, speaker: .user,
             text: "hello", audioPath: audioPath, startedAt: Date(),
             durationMs: 0, metricsJson: nil, isComplete: true)
    }

    // MARK: - resolving weak spots

    @Test func resolvingAWeakSpotPersistsAndShowsImmediately() async throws {
        let spot = Self.weakSpot("uses 'have finish'")
        let store = WeakSpotStore()
        try store.create(spot)
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(weakSpots: [spot])),
            sessionId: UUID(),
            weakSpotPersister: store
        )
        try await vm.load()
        #expect(vm.isResolved(spot) == false)

        vm.resolve(spot)

        #expect(vm.isResolved(spot))
        #expect(store.resolved == [spot.id])
        #expect(store.store[spot.id]?.status == .resolved)
    }

    /// Resolved spots leave `listActiveByFrequency`, which is what coach mode
    /// reads — that's the whole point of the button.
    @Test func aResolvedSpotStopsBeingTargetedByCoachMode() async throws {
        let spot = Self.weakSpot("uses 'have finish'")
        let store = WeakSpotStore()
        try store.create(spot)
        #expect(try store.listActiveByFrequency(limit: 5).count == 1)

        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(weakSpots: [spot])),
            sessionId: UUID(),
            weakSpotPersister: store
        )
        try await vm.load()
        vm.resolve(spot)

        #expect(try store.listActiveByFrequency(limit: 5).isEmpty)
    }

    /// The debrief is a cached snapshot, so a spot resolved after it was
    /// written would come back looking active unless status is re-read.
    @Test func aSpotResolvedEarlierShowsAsResolvedOnReload() async throws {
        let spot = Self.weakSpot("already fixed", status: .resolved)
        let store = WeakSpotStore()
        try store.create(spot)
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(weakSpots: [spot])),
            sessionId: UUID(),
            weakSpotPersister: store
        )

        try await vm.load()

        #expect(vm.isResolved(spot), "a cached debrief shouldn't resurrect a resolved spot")
    }

    @Test func aFailedResolveSurfacesAnErrorAndDoesNotMarkItDone() async throws {
        let spot = Self.weakSpot("p")
        let store = WeakSpotStore()
        try store.create(spot)
        store.resolveError = Boom()
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(weakSpots: [spot])),
            sessionId: UUID(),
            weakSpotPersister: store
        )
        try await vm.load()

        vm.resolve(spot)

        #expect(vm.isResolved(spot) == false)
        #expect(vm.lastError?.contains("Could not resolve") == true)
    }

    @Test func resolvingIsANoOpWithoutAPersister() async throws {
        let spot = Self.weakSpot("p")
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(weakSpots: [spot])),
            sessionId: UUID()
        )
        try await vm.load()
        vm.resolve(spot)
        #expect(vm.isResolved(spot) == false)
    }

    // MARK: - audio replay

    @Test func aTurnWithAReadableRecordingIsPlayable() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("debrief-audio-\(UUID().uuidString)", isDirectory: true)
        let relative = "audio/abc/user-turn-001.wav"
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 7, count: 128).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let playback = RecordingPlayback()
        let turn = Self.turn(audioPath: relative)
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(turns: [turn])),
            sessionId: UUID(),
            audioPlayback: playback,
            audioRoot: root
        )
        try await vm.load()

        #expect(vm.hasAudio(turn))
        await vm.play(turn)

        #expect(playback.played == [128], "the clip on disk should have been played")
        #expect(vm.playingTurnId == nil, "the playing flag must clear when done")
    }

    /// AI turns early in a session, and turns whose file was swept by the
    /// retention sweeper, have no clip — no button should appear.
    @Test func aTurnWithNoRecordingIsNotPlayable() async throws {
        let playback = RecordingPlayback()
        let missing = Self.turn(audioPath: "audio/gone/user-turn-009.wav")
        let none = Self.turn(audioPath: nil)
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(turns: [missing, none])),
            sessionId: UUID(),
            audioPlayback: playback,
            audioRoot: URL(fileURLWithPath: "/nonexistent-root")
        )
        try await vm.load()

        #expect(vm.hasAudio(missing) == false)
        #expect(vm.hasAudio(none) == false)
        await vm.play(missing)
        #expect(playback.played.isEmpty)
    }

    @Test func aFailedPlaybackSurfacesAnError() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("debrief-audio-\(UUID().uuidString)", isDirectory: true)
        let relative = "audio/abc/user-turn-001.wav"
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 7, count: 64).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let playback = RecordingPlayback()
        playback.error = Boom()
        let turn = Self.turn(audioPath: relative)
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(turns: [turn])),
            sessionId: UUID(),
            audioPlayback: playback,
            audioRoot: root
        )
        try await vm.load()

        await vm.play(turn)

        #expect(vm.lastError?.contains("Couldn't play") == true)
        #expect(vm.playingTurnId == nil)
    }

    @Test func playingIsANoOpWithoutAPlaybackAdapter() async throws {
        let turn = Self.turn(audioPath: "audio/a/b.wav")
        let vm = DebriefViewModel(
            analyzer: StubAnalyzer(debrief: Self.debrief(turns: [turn])),
            sessionId: UUID()
        )
        try await vm.load()
        #expect(vm.hasAudio(turn) == false)
        await vm.play(turn)
        #expect(vm.lastError == nil)
    }
}
