import Foundation
import Core
import Persistence

func main() throws {
    let dbPath = URL(fileURLWithPath: "/tmp/eng-assistant-smoke.sqlite")
    if FileManager.default.fileExists(atPath: dbPath.path) {
        try FileManager.default.removeItem(at: dbPath)
    }

    print("→ Opening DB at \(dbPath.path)")
    let db = try Database.onDisk(at: dbPath)

    print("→ Loading built-in scenarios")
    let catalog = try ScenarioCatalog.loadBuiltIn()
    print("  loaded \(catalog.allScenarios.count) scenarios")

    let scenario = catalog.scenario(id: "work-standup-01")!
    print("→ Using scenario: \(scenario.title)")

    let sessionRepo = SessionRepository(database: db)
    let turnRepo = TurnRepository(database: db)
    let weakRepo = WeakSpotRepository(database: db)

    let sessionId = UUID()
    let session = Session(
        id: sessionId,
        scenarioId: scenario.id,
        startedAt: Date(),
        endedAt: nil,
        mode: .flow,
        status: .active,
        summary: nil,
        personaSnapshot: scenario.persona
    )
    try sessionRepo.create(session)
    print("→ Created session \(sessionId.uuidString.prefix(8))…")

    let turns: [(Speaker, String)] = [
        (.ai, scenario.openingLine),
        (.user, "Yesterday I finished the auth refactor. Today I'm picking up the rate-limiter."),
        (.ai, "Any blockers I should know about?"),
        (.user, "No blockers, but I'd like a review on the auth PR before EOD."),
    ]
    for (i, (speaker, text)) in turns.enumerated() {
        let t = Turn(
            id: UUID(),
            sessionId: sessionId,
            turnIndex: i,
            speaker: speaker,
            text: text,
            audioPath: nil,
            startedAt: Date(),
            durationMs: 3000,
            metricsJson: nil,
            isComplete: true
        )
        try turnRepo.append(t)
    }
    print("→ Appended \(turns.count) turns")

    let ws = WeakSpot(
        id: UUID(),
        pattern: "uses passive 'I'd like a review' instead of asking directly",
        category: .vocab,
        firstSeen: Date(),
        lastSeen: Date(),
        occurrenceCount: 1,
        status: .active,
        exampleTurnIds: []
    )
    try weakRepo.create(ws)
    print("→ Recorded 1 weak spot")

    try sessionRepo.finalize(id: sessionId, endedAt: Date(), summary: "Standup practice run.")
    print("→ Finalized session")

    let reload = try sessionRepo.find(id: sessionId)!
    let reloadedTurns = try turnRepo.list(forSession: sessionId)
    let topWeakSpots = try weakRepo.listActiveByFrequency(limit: 5)

    print("\n=== Result ===")
    print("Session status: \(reload.status.rawValue)")
    print("Summary: \(reload.summary ?? "(none)")")
    print("Turns: \(reloadedTurns.count)")
    for t in reloadedTurns {
        print("  [\(t.turnIndex)] \(t.speaker.rawValue): \(t.text)")
    }
    print("Active weak spots: \(topWeakSpots.count)")
    for w in topWeakSpots {
        print("  - \(w.pattern) (\(w.category.rawValue), seen \(w.occurrenceCount)x)")
    }
}

do {
    try main()
    print("\n✓ smoke OK")
} catch {
    print("\n✗ smoke FAILED: \(error)")
    exit(1)
}
