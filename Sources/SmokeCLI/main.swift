import Foundation
import Core
import Persistence
import Fakes

func main() async throws {
    let dbPath = URL(fileURLWithPath: "/tmp/eng-assistant-engine-smoke.sqlite")
    if FileManager.default.fileExists(atPath: dbPath.path) {
        try FileManager.default.removeItem(at: dbPath)
    }

    print("→ Opening DB at \(dbPath.path)")
    let db = try Database.onDisk(at: dbPath)

    print("→ Loading scenario")
    let catalog = try ScenarioCatalog.loadBuiltIn()
    let scenario = catalog.scenario(id: "work-standup-01")!
    print("  scenario: \(scenario.title)")

    let sessionRepo = SessionRepository(database: db)
    let turnRepo = TurnRepository(database: db)

    let llm = FakeLLMProvider(scriptedReplyBatches: [
        ["I see — auth refactor done. ", "Any blockers I should know about?"],
        ["Got it. Let's plan the review for after standup."],
    ])
    let stt = FakeSTTProvider(scriptedTexts: [
        "Yesterday I finished the auth refactor. Today I'm picking up the rate-limiter.",
        "No blockers, but I'd like a review on the auth PR before EOD.",
    ])
    let tts = FakeTTSProvider()
    let capture = FakeAudioCapture(scriptedClipByteCounts: [1000, 1200])
    let playback = FakeAudioPlayback()

    let engine = SessionEngine(
        scenario: scenario,
        mode: .flow,
        activeWeakSpots: [],
        llm: llm,
        stt: stt,
        tts: tts,
        audioCapture: capture,
        audioPlayback: playback,
        sessionPersister: sessionRepo,
        turnPersister: turnRepo,
        voice: Voice(id: "default", displayName: "Default"),
        llmOptions: LLMOptions(modelName: "fake-llm")
    )

    print("→ Starting session")
    try await engine.start()

    print("→ Running user turn 1")
    _ = try await engine.runUserTurn()
    print("→ Running user turn 2")
    _ = try await engine.runUserTurn()

    print("→ Ending session")
    try await engine.end(summary: "Standup practice via fakes.")

    let session = (try await engine.sessionForTesting())!
    let allTurns = try turnRepo.list(forSession: session.id)

    print("\n=== Result ===")
    print("Session status: \(session.status.rawValue)")
    print("Summary: \(session.summary ?? "(none)")")
    print("Turns: \(allTurns.count)")
    for t in allTurns {
        print("  [\(t.turnIndex)] \(t.speaker.rawValue): \(t.text)")
    }
    let played = await playback.playedClipSizes
    let synthed = await tts.synthesizedTexts
    print("TTS calls: \(synthed.count)")
    print("Audio playbacks: \(played.count)")
}

do {
    try await main()
    print("\n✓ engine smoke OK")
} catch {
    print("\n✗ engine smoke FAILED: \(error)")
    exit(1)
}
