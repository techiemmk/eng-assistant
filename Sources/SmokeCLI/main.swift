import Foundation
import Core
import Persistence
import Fakes
import Adapters

func main() async throws {
    let live = CommandLine.arguments.contains("--live")
    let modelName = ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "qwen2.5:7b-instruct"

    let dbPath = URL(fileURLWithPath: "/tmp/eng-assistant-engine-smoke.sqlite")
    if FileManager.default.fileExists(atPath: dbPath.path) {
        try FileManager.default.removeItem(at: dbPath)
    }

    // Use a smoke-specific app-support folder so we don't pollute real user data.
    let layout = StorageLayout(appName: "EngAssistantSmoke")
    try layout.ensureDirectories()
    let audioStore = AudioFileStore(layout: layout)

    print("→ Mode: \(live ? "LIVE Ollama @ \(modelName)" : "fakes")")
    print("→ Opening DB at \(dbPath.path)")
    print("→ Audio root: \(layout.audioDirectory.path)")
    let db = try Database.onDisk(at: dbPath)

    print("→ Loading scenario")
    let catalog = try ScenarioCatalog.loadBuiltIn()
    let scenario = catalog.scenario(id: "work-standup-01")!
    print("  scenario: \(scenario.title)")

    let sessionRepo = SessionRepository(database: db)
    let turnRepo = TurnRepository(database: db)
    let weakSpotRepo = WeakSpotRepository(database: db)

    let engineLLM: LLMProvider
    let analysisLLM: LLMProvider
    if live {
        let client = URLSessionHTTPClient()
        engineLLM = OllamaLLM(httpClient: client)
        analysisLLM = OllamaLLM(httpClient: client)
    } else {
        engineLLM = FakeLLMProvider(scriptedReplyBatches: [
            ["I see — auth refactor done. ", "Any blockers I should know about?"],
            ["Got it. Let's plan the review for after standup."],
        ])
        analysisLLM = FakeLLMProvider(scriptedReplyBatches: [
            ["{\"grammarIssueCount\": 1}"],
            ["{\"grammarIssueCount\": 0}"],
            ["{\"patterns\":[{\"pattern\":\"uses passive 'I'd like a review' instead of asking directly\",\"category\":\"vocab\"}]}"],
        ])
    }

    let stt = FakeSTTProvider(scriptedTexts: [
        "Yesterday I have finish the auth refactor. Today I'm picking up the rate-limiter.",
        "No blockers, but I'd like a review on the auth PR before EOD.",
    ])
    let tts = FakeTTSProvider()
    let capture = FakeAudioCapture(scriptedClipByteCounts: [1000, 1200])
    let playback = FakeAudioPlayback()

    let engine = SessionEngine(
        scenario: scenario,
        mode: .flow,
        activeWeakSpots: [],
        llm: engineLLM,
        stt: stt,
        tts: tts,
        audioCapture: capture,
        audioPlayback: playback,
        sessionPersister: sessionRepo,
        turnPersister: turnRepo,
        voice: Voice(id: "default", displayName: "Default"),
        llmOptions: LLMOptions(modelName: modelName),
        audioFilePersister: audioStore
    )

    print("→ Starting session")
    try await engine.start()
    print("→ User turn 1"); _ = try await engine.runUserTurn()
    print("→ User turn 2"); _ = try await engine.runUserTurn()
    print("→ Ending session")
    try await engine.end(summary: live ? "Live standup practice." : "Fake standup practice.")

    let session = (try await engine.sessionForTesting())!

    print("→ Running post-session analysis")
    let analyzer = SessionAnalyzer(
        grammarJudge: GrammarJudge(llm: analysisLLM, options: LLMOptions(modelName: modelName)),
        weakSpotExtractor: WeakSpotExtractor(llm: analysisLLM, options: LLMOptions(modelName: modelName)),
        weakSpotMerger: WeakSpotMerger(persister: weakSpotRepo),
        sessionPersister: sessionRepo,
        turnPersister: turnRepo,
        scenarioCatalog: catalog
    )
    let debrief = try await analyzer.analyze(sessionId: session.id)

    print("\n=== Debrief ===")
    print("Summary: \(debrief.summary)")
    print("Session metrics:")
    print("  user turns: \(debrief.sessionMetrics.userTurnCount)")
    print("  total words: \(debrief.sessionMetrics.totalWordCount)")
    print("  fillers: \(debrief.sessionMetrics.totalFillerCount)")
    print("  grammar issues: \(debrief.sessionMetrics.totalGrammarIssues)")
    print(String(format: "  avg unique-word ratio: %.2f", debrief.sessionMetrics.averageUniqueWordRatio))
    print(String(format: "  avg filler density: %.3f", debrief.sessionMetrics.averageFillerDensity))
    if !debrief.newlyCreatedWeakSpots.isEmpty {
        print("New weak spots:")
        for ws in debrief.newlyCreatedWeakSpots {
            print("  + \(ws.pattern) (\(ws.category.rawValue))")
        }
    }
    if !debrief.recurringWeakSpots.isEmpty {
        print("Recurring weak spots:")
        for ws in debrief.recurringWeakSpots {
            print("  ↑ \(ws.pattern) (seen \(ws.occurrenceCount)×)")
        }
    }
    if !debrief.suggestedDrills.isEmpty {
        print("Suggested drills:")
        for d in debrief.suggestedDrills {
            print("  • \(d)")
        }
    }

    let pathfulTurns = debrief.allTurns.filter { $0.audioPath != nil }
    if !pathfulTurns.isEmpty {
        print("Persisted audio:")
        for t in pathfulTurns {
            print("  [\(t.turnIndex)] \(t.speaker.rawValue): \(t.audioPath ?? "")")
        }
    }
}

do {
    try await main()
    print("\n✓ smoke OK")
} catch {
    print("\n✗ smoke FAILED: \(error)")
    exit(1)
}
