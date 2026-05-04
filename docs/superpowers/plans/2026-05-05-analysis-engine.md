# Analysis Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a finished session into a debrief. Given a session id, produce per-turn and session-level metrics, extract recurring weak spots from the transcript (LLM-driven, deduplicated against the existing `weak_spots` table), and assemble a `Debrief` value containing everything the future UI will render. End state: SmokeCLI runs a fake session, analyzes it, and prints a real debrief.

**Architecture:** All analysis logic lives in `Core` and depends only on existing protocols (`LLMProvider`, `TurnPersisting`, `WeakSpotPersisting`). Heuristic metrics (filler density, unique-word ratio) come from text alone — no audio yet, that's Plan 5. The LLM is used for two things: per-turn grammar issue count (LLM-as-judge with strict JSON output) and weak-spot extraction (LLM identifies recurring patterns from the transcript). Both pieces use scripted `FakeLLMProvider` in tests; real providers land in Plan 4.

**Tech Stack:** Swift 5.9+, Swift Package Manager, Swift Structured Concurrency, Swift Testing.

**Test runner:** Use `bin/test.sh` (NOT `swift test`) per the CLT setup. Test framework is **Swift Testing** (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`).

**Git committer:** All implementer subagents are dispatched with `git -c user.email=techiemmk@gmail.com -c user.name="Manoj"` (no global git config in this environment).

**Branching:** Plan 3 is implemented directly on `main`. No feature branch.

---

## File Structure

```
Sources/
├── Core/
│   ├── Engine/                          # extends existing
│   │   ├── TextMetricsCalculator.swift  # NEW — heuristic per-turn text metrics
│   │   ├── FillerDictionary.swift       # NEW — list of common English fillers
│   │   ├── GrammarJudge.swift           # NEW — LLM-as-judge for grammar issue count
│   │   ├── MetricsAnalyzer.swift        # NEW — orchestrates per-turn + session metrics
│   │   ├── WeakSpotExtractor.swift      # NEW — LLM extracts WeakSpotCandidate list
│   │   ├── WeakSpotMerger.swift         # NEW — dedupes candidates against existing rows
│   │   ├── CoachingEngine.swift         # NEW — composes Debrief from analysis output
│   │   └── SessionAnalyzer.swift        # NEW — top-level orchestrator
│   ├── Models/
│   │   └── Debrief.swift                # NEW — value type containing the full analysis
│   └── Persisters/
│       ├── TurnPersisting.swift         # MODIFY — re-add updateMetricsJson
│       └── WeakSpotPersisting.swift     # MODIFY — add create, findByPattern, incrementOccurrence

Tests/
└── CoreTests/
    ├── TextMetricsCalculatorTests.swift     # NEW
    ├── GrammarJudgeTests.swift              # NEW
    ├── MetricsAnalyzerTests.swift           # NEW
    ├── WeakSpotExtractorTests.swift         # NEW
    ├── WeakSpotMergerTests.swift            # NEW
    ├── CoachingEngineTests.swift            # NEW
    └── SessionAnalyzerTests.swift           # NEW
```

**Per-file responsibility:**

| File | Responsibility |
|---|---|
| `FillerDictionary.swift` | Static list of common spoken-English filler words/phrases (`um`, `uh`, `like`, `you know`, `I mean`, etc.). Used by `TextMetricsCalculator`. |
| `TextMetricsCalculator.swift` | Pure-function heuristic analysis: filler count, total word count, unique-word ratio, filler density. Operates on a single `Turn.text`. No LLM. |
| `GrammarJudge.swift` | One LLM call per turn (or per batch) that returns a strict JSON `{"grammarIssueCount": N}`. Uses `LLMProvider`. Tolerant of malformed JSON. |
| `MetricsAnalyzer.swift` | For each user turn in a session: runs `TextMetricsCalculator` + `GrammarJudge`, builds a `TurnMetrics`, persists via `turnPersister.updateMetricsJson(...)`. Then aggregates a `SessionMetrics` value. |
| `WeakSpotExtractor.swift` | One LLM call over the whole user-turn transcript, returns `[WeakSpotCandidate]` (pattern + category). Tolerant of malformed JSON. |
| `WeakSpotMerger.swift` | Takes `[WeakSpotCandidate]` and the existing user weak spots; for each candidate, either upsert (increment occurrence on existing match by pattern) or create. Returns `(newlyCreated: [WeakSpot], recurring: [WeakSpot])`. |
| `CoachingEngine.swift` | Pure function that composes a `Debrief` from session, turns, metrics, and weak-spot results. No I/O. |
| `SessionAnalyzer.swift` | Top-level orchestrator. Loads turns, runs MetricsAnalyzer, runs WeakSpotExtractor, runs WeakSpotMerger, calls CoachingEngine. Returns a `Debrief`. |
| `Debrief.swift` | Value type bundling everything the UI will render: session, summary string, per-turn metrics, session metrics, new vs recurring weak spots, suggested drills. |

---

## Task Decomposition Notes

- TDD throughout. Every task: failing test → run (red) → minimal impl → run (green) → commit.
- Use scripted `FakeLLMProvider` for both `GrammarJudge` and `WeakSpotExtractor` tests.
- Each commit must leave `bin/test.sh` all green.
- The plan is implemented directly on `main` — no feature branch.

---

## Task 1 — Persister protocol extensions

Re-add `updateMetricsJson` to `TurnPersisting` (it has a real caller now: `MetricsAnalyzer`). Expand `WeakSpotPersisting` so `WeakSpotMerger` can dedupe.

**Files:**
- Modify: `Sources/Core/Persisters/TurnPersisting.swift`
- Modify: `Sources/Core/Persisters/WeakSpotPersisting.swift`
- Modify: `Tests/PersistenceTests/PersisterConformanceTests.swift` (add tests for the new conformance methods)
- Modify: `Tests/CoreTests/SessionEngineTests.swift` — `InMemoryTurnPersister` re-adds the `updateMetricsJson` method

- [ ] **Step 1 — Update `TurnPersisting`**

`Sources/Core/Persisters/TurnPersisting.swift`:
```swift
import Foundation

public protocol TurnPersisting: Sendable {
    func append(_ turn: Turn) throws
    func list(forSession sessionId: UUID) throws -> [Turn]
    func markIncomplete(id: UUID) throws
    func updateMetricsJson(turnId: UUID, json: String) throws
}
```

- [ ] **Step 2 — Update `WeakSpotPersisting`**

`Sources/Core/Persisters/WeakSpotPersisting.swift`:
```swift
import Foundation

public protocol WeakSpotPersisting: Sendable {
    func listActiveByFrequency(limit: Int) throws -> [WeakSpot]
    func create(_ weakSpot: WeakSpot) throws
    func findByPattern(_ pattern: String) throws -> WeakSpot?
    func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws
}
```

The concrete `WeakSpotRepository` (Plan 1) already has all four methods, so its conformance still works.

- [ ] **Step 3 — Re-add the missing method to the in-memory test fake**

In `Tests/CoreTests/SessionEngineTests.swift`, add this method back into `InMemoryTurnPersister`:

```swift
    func updateMetricsJson(turnId: UUID, json: String) throws {
        if let i = turns.firstIndex(where: { $0.id == turnId }) { turns[i].metricsJson = json }
    }
```

- [ ] **Step 4 — Extend the persistence conformance test**

In `Tests/PersistenceTests/PersisterConformanceTests.swift`, add tests proving `TurnRepository.updateMetricsJson` and `WeakSpotRepository.create`/`findByPattern`/`incrementOccurrence` are reachable through the protocol:

```swift
    @Test func turnRepositoryConformsToFullTurnPersisting() throws {
        let db = try Database.inMemory()
        let sessionRepo = SessionRepository(database: db)
        let sessionId = UUID()
        try sessionRepo.create(Session(
            id: sessionId, scenarioId: "s", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        ))
        let repo: any TurnPersisting = TurnRepository(database: db)
        let turnId = UUID()
        try repo.append(Turn(
            id: turnId, sessionId: sessionId, turnIndex: 0, speaker: .user,
            text: "hi", audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        ))
        try repo.updateMetricsJson(turnId: turnId, json: "{\"a\":1}")
        let after = try repo.list(forSession: sessionId).first
        #expect(after?.metricsJson == "{\"a\":1}")
    }

    @Test func weakSpotRepositoryConformsToFullWeakSpotPersisting() throws {
        let db = try Database.inMemory()
        let repo: any WeakSpotPersisting = WeakSpotRepository(database: db)
        let now = Date()
        let id = UUID()
        try repo.create(WeakSpot(
            id: id, pattern: "p", category: .grammar,
            firstSeen: now, lastSeen: now,
            occurrenceCount: 1, status: .active, exampleTurnIds: []
        ))
        let found = try repo.findByPattern("p")
        #expect(found?.id == id)
        try repo.incrementOccurrence(id: id, lastSeen: now.addingTimeInterval(60), addExampleTurnId: UUID())
        let updated = try repo.findByPattern("p")
        #expect(updated?.occurrenceCount == 2)
    }
```

- [ ] **Step 5 — Verify**

```bash
bin/test.sh
```

Expected: 76 (existing) + 2 (new) = 78 tests in 24 suites, all green.

- [ ] **Step 6 — Commit**

```bash
git add Sources/Core/Persisters/TurnPersisting.swift \
        Sources/Core/Persisters/WeakSpotPersisting.swift \
        Tests/CoreTests/SessionEngineTests.swift \
        Tests/PersistenceTests/PersisterConformanceTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): expand TurnPersisting + WeakSpotPersisting for analysis"
```

---

## Task 2 — `FillerDictionary` + `TextMetricsCalculator`

Pure-function text analysis that doesn't depend on audio or the LLM. Produces filler count, total word count, unique-word ratio, filler density.

**Files:**
- Create: `Sources/Core/Engine/FillerDictionary.swift`
- Create: `Sources/Core/Engine/TextMetricsCalculator.swift`
- Create: `Tests/CoreTests/TextMetricsCalculatorTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/TextMetricsCalculatorTests.swift`:
```swift
import Testing
@testable import Core

@Suite struct TextMetricsCalculatorTests {
    @Test func emptyTextProducesZeroMetrics() {
        let m = TextMetricsCalculator.calculate(text: "")
        #expect(m.totalWordCount == 0)
        #expect(m.uniqueWordCount == 0)
        #expect(m.fillerCount == 0)
        #expect(m.uniqueWordRatio == 0)
        #expect(m.fillerDensity == 0)
    }

    @Test func wordCountsSimpleSentence() {
        let m = TextMetricsCalculator.calculate(text: "The quick brown fox jumps")
        #expect(m.totalWordCount == 5)
        #expect(m.uniqueWordCount == 5)
        #expect(m.uniqueWordRatio == 1.0)
    }

    @Test func uniqueRatioReflectsRepetition() {
        let m = TextMetricsCalculator.calculate(text: "the the the cat cat sat")
        #expect(m.totalWordCount == 6)
        #expect(m.uniqueWordCount == 3)
        #expect(abs(m.uniqueWordRatio - 0.5) < 0.001)
    }

    @Test func detectsCommonFillers() {
        let m = TextMetricsCalculator.calculate(text: "Um, I think that, uh, you know, the project is going well.")
        // "um", "uh", "you know" — three fillers (you-know counts as one phrase).
        #expect(m.fillerCount == 3)
        #expect(m.fillerDensity > 0)
    }

    @Test func caseInsensitiveAndStripsBasicPunctuation() {
        let m = TextMetricsCalculator.calculate(text: "Like, LIKE, like!")
        #expect(m.fillerCount == 3)
    }

    @Test func multiwordFillersDetected() {
        let m = TextMetricsCalculator.calculate(text: "I mean, you know, sort of, kind of finished it.")
        // "I mean", "you know", "sort of", "kind of" — four phrase-fillers.
        #expect(m.fillerCount == 4)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter TextMetricsCalculatorTests
```

Expected: compile error — `TextMetricsCalculator` not found.

- [ ] **Step 3 — Implement `FillerDictionary`**

`Sources/Core/Engine/FillerDictionary.swift`:
```swift
import Foundation

/// English fillers commonly produced by ESL speakers practicing fluency.
/// All entries are lowercase. Multi-word phrases are matched as whole-word
/// sequences (whitespace-separated) — punctuation is stripped before matching.
public enum FillerDictionary {
    public static let singleWord: Set<String> = [
        "um", "uh", "uhh", "ehm", "er", "erm",
        "like", "actually", "basically", "literally",
        "right", "okay", "ok", "well", "anyway",
    ]

    public static let phrases: [[String]] = [
        ["you", "know"],
        ["i", "mean"],
        ["sort", "of"],
        ["kind", "of"],
        ["i", "guess"],
        ["or", "something"],
        ["or", "whatever"],
    ]
}
```

- [ ] **Step 4 — Implement `TextMetricsCalculator`**

`Sources/Core/Engine/TextMetricsCalculator.swift`:
```swift
import Foundation

public struct TextMetrics: Equatable, Sendable {
    public let totalWordCount: Int
    public let uniqueWordCount: Int
    public let fillerCount: Int
    public var uniqueWordRatio: Double {
        guard totalWordCount > 0 else { return 0 }
        return Double(uniqueWordCount) / Double(totalWordCount)
    }
    public var fillerDensity: Double {
        guard totalWordCount > 0 else { return 0 }
        return Double(fillerCount) / Double(totalWordCount)
    }

    public init(totalWordCount: Int, uniqueWordCount: Int, fillerCount: Int) {
        self.totalWordCount = totalWordCount
        self.uniqueWordCount = uniqueWordCount
        self.fillerCount = fillerCount
    }
}

public enum TextMetricsCalculator {
    public static func calculate(text: String) -> TextMetrics {
        let words = tokenize(text)
        guard !words.isEmpty else {
            return TextMetrics(totalWordCount: 0, uniqueWordCount: 0, fillerCount: 0)
        }
        let unique = Set(words)
        let fillerCount = countFillers(in: words)
        return TextMetrics(
            totalWordCount: words.count,
            uniqueWordCount: unique.count,
            fillerCount: fillerCount
        )
    }

    /// Lowercase, split on whitespace, strip surrounding punctuation. We don't
    /// strip in-word apostrophes ("don't", "I'm") — fluency analysis depends on them.
    private static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let punctuation = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))
        return lowered
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: punctuation) }
            .filter { !$0.isEmpty }
    }

    private static func countFillers(in words: [String]) -> Int {
        var count = 0
        var i = 0
        while i < words.count {
            // Try phrase fillers first (longest match).
            var matchedPhraseLength = 0
            for phrase in FillerDictionary.phrases {
                if i + phrase.count <= words.count,
                   Array(words[i..<i + phrase.count]) == phrase {
                    matchedPhraseLength = max(matchedPhraseLength, phrase.count)
                }
            }
            if matchedPhraseLength > 0 {
                count += 1
                i += matchedPhraseLength
                continue
            }
            if FillerDictionary.singleWord.contains(words[i]) {
                count += 1
            }
            i += 1
        }
        return count
    }
}
```

- [ ] **Step 5 — Confirm green**

```bash
bin/test.sh --filter TextMetricsCalculatorTests
bin/test.sh
```

Expected: 6 new tests pass; full suite (now 84 tests in 25 suites) all green.

- [ ] **Step 6 — Commit**

```bash
git add Sources/Core/Engine/FillerDictionary.swift \
        Sources/Core/Engine/TextMetricsCalculator.swift \
        Tests/CoreTests/TextMetricsCalculatorTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add TextMetricsCalculator + FillerDictionary"
```

---

## Task 3 — `GrammarJudge` (LLM-as-judge)

Asks the LLM, "how many clear grammatical errors are in this user utterance?" and parses a strict JSON reply. Tolerant of malformed JSON (returns 0 with a flag).

**Files:**
- Create: `Sources/Core/Engine/GrammarJudge.swift`
- Create: `Tests/CoreTests/GrammarJudgeTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/GrammarJudgeTests.swift`:
```swift
import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct GrammarJudgeTests {
    @Test func parsesValidJsonResponse() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": 2}"])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "I are happy and goes home")
        #expect(count == 2)
    }

    @Test func toleratesExtraWhitespaceAndQuotes() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["  { \"grammarIssueCount\" : 5 }  \n"])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "anything")
        #expect(count == 5)
    }

    @Test func returnsZeroOnMalformedJson() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["I think there are about 3 errors."])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "anything")
        #expect(count == 0)
    }

    @Test func returnsZeroOnNegativeOrAbsurdValue() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": -3}"])
        let judge = GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake"))
        let count = try await judge.countIssues(in: "anything")
        #expect(count == 0)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter GrammarJudgeTests
```

Expected: compile error — `GrammarJudge` not found.

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/GrammarJudge.swift`:
```swift
import Foundation

public struct GrammarJudge: Sendable {
    private let llm: LLMProvider
    private let options: LLMOptions

    public init(llm: LLMProvider, options: LLMOptions) {
        self.llm = llm
        self.options = options
    }

    /// Returns the number of clear grammatical errors the LLM identifies in `text`.
    /// Returns 0 if the LLM response cannot be parsed as the expected JSON shape.
    public func countIssues(in text: String) async throws -> Int {
        let system = ChatMessage(role: .system, content: """
            You are a strict grammar judge. The user will give you one English utterance.
            Reply with ONLY a JSON object of the form {"grammarIssueCount": N} where N
            is the number of clear, unambiguous grammatical errors (subject-verb
            agreement, tense, article, preposition, etc.). Do not count stylistic
            choices or filler words. No prose, no explanation, no markdown — just JSON.
            """)
        let user = ChatMessage(role: .user, content: text)
        let stream = try await llm.respond(messages: [system, user], options: options)
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        return parseCount(from: collected)
    }

    private func parseCount(from raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let n = obj["grammarIssueCount"] as? Int,
              n >= 0
        else {
            return 0
        }
        return n
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter GrammarJudgeTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 88 tests in 26 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/GrammarJudge.swift Tests/CoreTests/GrammarJudgeTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add GrammarJudge for LLM-as-judge grammar count"
```

---

## Task 4 — `MetricsAnalyzer`

Per user turn: combines `TextMetricsCalculator` + `GrammarJudge` into a `TurnMetrics` row, persists it via `turnPersister.updateMetricsJson(...)`. After processing every user turn, aggregates a `SessionMetrics` value.

**Files:**
- Create: `Sources/Core/Engine/MetricsAnalyzer.swift`
- Create: `Tests/CoreTests/MetricsAnalyzerTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/MetricsAnalyzerTests.swift`:
```swift
import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct MetricsAnalyzerTests {
    private static func makeUserTurn(_ text: String, sessionId: UUID, index: Int) -> Turn {
        Turn(
            id: UUID(), sessionId: sessionId, turnIndex: index, speaker: .user,
            text: text, audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        )
    }

    private static func makeAITurn(_ text: String, sessionId: UUID, index: Int) -> Turn {
        Turn(
            id: UUID(), sessionId: sessionId, turnIndex: index, speaker: .ai,
            text: text, audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        )
    }

    final class CapturingPersister: TurnPersisting, @unchecked Sendable {
        var stored: [(turnId: UUID, json: String)] = []
        func append(_ turn: Turn) throws {}
        func list(forSession sessionId: UUID) throws -> [Turn] { [] }
        func markIncomplete(id: UUID) throws {}
        func updateMetricsJson(turnId: UUID, json: String) throws {
            stored.append((turnId, json))
        }
    }

    @Test func computesTurnMetricsForEachUserTurnAndPersistsThem() async throws {
        let sessionId = UUID()
        let turns: [Turn] = [
            Self.makeAITurn("Good morning.", sessionId: sessionId, index: 0),
            Self.makeUserTurn("Um, yesterday I have finish the auth refactor.", sessionId: sessionId, index: 1),
            Self.makeAITurn("Great.", sessionId: sessionId, index: 2),
            Self.makeUserTurn("You know, I think it goes well.", sessionId: sessionId, index: 3),
        ]
        let llm = FakeLLMProvider(scriptedReplyBatches: [
            ["{\"grammarIssueCount\": 2}"],     // for user turn 1
            ["{\"grammarIssueCount\": 1}"],     // for user turn 3
        ])
        let persister = CapturingPersister()
        let analyzer = MetricsAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            turnPersister: persister
        )
        let session = await analyzer.analyze(turns: turns)
        #expect(persister.stored.count == 2)
        #expect(session.userTurnCount == 2)
        #expect(session.totalGrammarIssues == 3)
        #expect(session.totalFillerCount > 0)  // "um", "you know"
        #expect(session.averageUniqueWordRatio > 0)
    }

    @Test func emptyTranscriptProducesZeroSessionMetrics() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": 0}"])
        let persister = CapturingPersister()
        let analyzer = MetricsAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            turnPersister: persister
        )
        let session = await analyzer.analyze(turns: [])
        #expect(session.userTurnCount == 0)
        #expect(session.totalGrammarIssues == 0)
        #expect(session.totalFillerCount == 0)
        #expect(persister.stored.isEmpty)
    }

    @Test func skipsAITurnsAndIncompleteUserTurns() async throws {
        let sessionId = UUID()
        var incomplete = Self.makeUserTurn("oh no", sessionId: sessionId, index: 1)
        incomplete.isComplete = false
        let turns: [Turn] = [
            Self.makeAITurn("hi", sessionId: sessionId, index: 0),
            incomplete,
            Self.makeUserTurn("I am ready.", sessionId: sessionId, index: 2),
        ]
        let llm = FakeLLMProvider(scriptedReplies: ["{\"grammarIssueCount\": 0}"])
        let persister = CapturingPersister()
        let analyzer = MetricsAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            turnPersister: persister
        )
        let session = await analyzer.analyze(turns: turns)
        #expect(session.userTurnCount == 1)
        #expect(persister.stored.count == 1)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter MetricsAnalyzerTests
```

Expected: compile error — `MetricsAnalyzer`, `SessionMetrics` not found.

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/MetricsAnalyzer.swift`:
```swift
import Foundation

/// Aggregated per-session metrics. Not persisted as a row of its own — the
/// per-turn `metrics_json` is the source of truth; this is computed for the
/// current debrief and (later) feeds `metrics_daily` rollups.
public struct SessionMetrics: Equatable, Sendable {
    public let userTurnCount: Int
    public let totalWordCount: Int
    public let totalFillerCount: Int
    public let totalGrammarIssues: Int
    public let averageUniqueWordRatio: Double
    public let averageFillerDensity: Double

    public init(
        userTurnCount: Int,
        totalWordCount: Int,
        totalFillerCount: Int,
        totalGrammarIssues: Int,
        averageUniqueWordRatio: Double,
        averageFillerDensity: Double
    ) {
        self.userTurnCount = userTurnCount
        self.totalWordCount = totalWordCount
        self.totalFillerCount = totalFillerCount
        self.totalGrammarIssues = totalGrammarIssues
        self.averageUniqueWordRatio = averageUniqueWordRatio
        self.averageFillerDensity = averageFillerDensity
    }
}

public struct MetricsAnalyzer: Sendable {
    private let grammarJudge: GrammarJudge
    private let turnPersister: TurnPersisting

    public init(grammarJudge: GrammarJudge, turnPersister: TurnPersisting) {
        self.grammarJudge = grammarJudge
        self.turnPersister = turnPersister
    }

    public func analyze(turns: [Turn]) async -> SessionMetrics {
        let userTurns = turns.filter { $0.speaker == .user && $0.isComplete }
        var totalWordCount = 0
        var totalFillerCount = 0
        var totalGrammar = 0
        var sumUniqueRatios = 0.0
        var sumFillerDensities = 0.0
        let encoder = JSONEncoder()

        for turn in userTurns {
            let text = TextMetricsCalculator.calculate(text: turn.text)
            // GrammarJudge errors are swallowed at this level — a single LLM
            // hiccup shouldn't void the whole session's metrics.
            let grammarCount = (try? await grammarJudge.countIssues(in: turn.text)) ?? 0
            let metrics = TurnMetrics(
                wordsPerMinute: 0,           // populated in Plan 5 once audio durations land
                pauseRatio: 0,               // ditto
                fillerCount: text.fillerCount,
                uniqueWordRatio: text.uniqueWordRatio,
                grammarIssueCount: grammarCount
            )
            if let data = try? encoder.encode(metrics),
               let json = String(data: data, encoding: .utf8) {
                try? turnPersister.updateMetricsJson(turnId: turn.id, json: json)
            }
            totalWordCount += text.totalWordCount
            totalFillerCount += text.fillerCount
            totalGrammar += grammarCount
            sumUniqueRatios += text.uniqueWordRatio
            sumFillerDensities += text.fillerDensity
        }

        let n = max(userTurns.count, 1)
        return SessionMetrics(
            userTurnCount: userTurns.count,
            totalWordCount: totalWordCount,
            totalFillerCount: totalFillerCount,
            totalGrammarIssues: totalGrammar,
            averageUniqueWordRatio: sumUniqueRatios / Double(n),
            averageFillerDensity: sumFillerDensities / Double(n)
        )
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter MetricsAnalyzerTests
bin/test.sh
```

Expected: 3 new tests pass; full suite (now 91 tests in 27 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/MetricsAnalyzer.swift Tests/CoreTests/MetricsAnalyzerTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add MetricsAnalyzer (per-turn + session metrics)"
```

---

## Task 5 — `WeakSpotExtractor`

Single LLM call over the entire user transcript that returns `[WeakSpotCandidate]` — pattern + category. Tolerant of malformed JSON.

**Files:**
- Create: `Sources/Core/Engine/WeakSpotExtractor.swift`
- Create: `Tests/CoreTests/WeakSpotExtractorTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/WeakSpotExtractorTests.swift`:
```swift
import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct WeakSpotExtractorTests {
    @Test func parsesValidJsonArray() async throws {
        let json = """
            {"patterns":[
                {"pattern":"uses 'more better' instead of 'better'","category":"grammar"},
                {"pattern":"stutters on conditionals","category":"fluency"}
            ]}
            """
        let llm = FakeLLMProvider(scriptedReplies: [json])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "Some text.")
        #expect(result.count == 2)
        #expect(result[0].pattern == "uses 'more better' instead of 'better'")
        #expect(result[0].category == .grammar)
        #expect(result[1].category == .fluency)
    }

    @Test func emptyTranscriptReturnsEmpty() async throws {
        let llm = FakeLLMProvider(scriptedReplies: [""])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "")
        #expect(result.isEmpty)
    }

    @Test func malformedJsonReturnsEmptyAndDoesNotThrow() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["I see issues with conditionals and tense."])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "anything")
        #expect(result.isEmpty)
    }

    @Test func unknownCategoryFallsBackToGrammar() async throws {
        let json = """
            {"patterns":[{"pattern":"x","category":"weird-unknown"}]}
            """
        let llm = FakeLLMProvider(scriptedReplies: [json])
        let extractor = WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake"))
        let result = try await extractor.extract(fromUserTranscript: "anything")
        #expect(result.count == 1)
        #expect(result[0].category == .grammar)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter WeakSpotExtractorTests
```

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/WeakSpotExtractor.swift`:
```swift
import Foundation

public struct WeakSpotCandidate: Equatable, Sendable {
    public let pattern: String
    public let category: WeakSpotCategory

    public init(pattern: String, category: WeakSpotCategory) {
        self.pattern = pattern
        self.category = category
    }
}

public struct WeakSpotExtractor: Sendable {
    private let llm: LLMProvider
    private let options: LLMOptions

    public init(llm: LLMProvider, options: LLMOptions) {
        self.llm = llm
        self.options = options
    }

    public func extract(fromUserTranscript transcript: String) async throws -> [WeakSpotCandidate] {
        guard !transcript.isEmpty else { return [] }
        let system = ChatMessage(role: .system, content: """
            You analyze an English-learner's spoken transcript and identify recurring
            (not one-off) mistakes worth coaching. Reply with ONLY a JSON object:
            {"patterns": [{"pattern": "<short phrase>", "category": "<grammar|vocab|filler|fluency>"}, ...]}
            Each pattern is a 1-line description (e.g. "uses 'more better' instead of 'better'").
            If no recurring patterns stand out, return {"patterns": []}.
            No prose, no markdown — just JSON.
            """)
        let user = ChatMessage(role: .user, content: transcript)
        let stream = try await llm.respond(messages: [system, user], options: options)
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        return parse(collected)
    }

    private func parse(_ raw: String) -> [WeakSpotCandidate] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["patterns"] as? [[String: Any]]
        else {
            return []
        }
        return arr.compactMap { entry in
            guard let pattern = entry["pattern"] as? String, !pattern.isEmpty else { return nil }
            let categoryStr = (entry["category"] as? String) ?? "grammar"
            let category = WeakSpotCategory(rawValue: categoryStr) ?? .grammar
            return WeakSpotCandidate(pattern: pattern, category: category)
        }
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter WeakSpotExtractorTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 95 tests in 28 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/WeakSpotExtractor.swift Tests/CoreTests/WeakSpotExtractorTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add WeakSpotExtractor (LLM-driven pattern extraction)"
```

---

## Task 6 — `WeakSpotMerger`

Takes `[WeakSpotCandidate]` plus a list of recent user `Turn`s (so we can attach example turn ids to weak spots) and dedupes against the `WeakSpotPersisting` store. Returns `(newlyCreated: [WeakSpot], recurring: [WeakSpot])`.

Pattern equivalence is exact-string match for v1. (Fuzzy matching is a future improvement.)

**Files:**
- Create: `Sources/Core/Engine/WeakSpotMerger.swift`
- Create: `Tests/CoreTests/WeakSpotMergerTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/WeakSpotMergerTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Core

@Suite struct WeakSpotMergerTests {
    final class InMemoryWeakSpotPersister: WeakSpotPersisting, @unchecked Sendable {
        var store: [UUID: WeakSpot] = [:]
        func listActiveByFrequency(limit: Int) throws -> [WeakSpot] {
            store.values.filter { $0.status == .active }
                .sorted { $0.occurrenceCount > $1.occurrenceCount }
                .prefix(limit).map { $0 }
        }
        func create(_ ws: WeakSpot) throws { store[ws.id] = ws }
        func findByPattern(_ pattern: String) throws -> WeakSpot? {
            store.values.first { $0.pattern == pattern }
        }
        func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
            guard var ws = store[id] else { return }
            ws.occurrenceCount += 1
            ws.lastSeen = lastSeen
            if let t = addExampleTurnId, !ws.exampleTurnIds.contains(t) {
                ws.exampleTurnIds.append(t)
            }
            store[id] = ws
        }
    }

    @Test func newPatternIsCreated() async throws {
        let store = InMemoryWeakSpotPersister()
        let merger = WeakSpotMerger(persister: store)
        let now = Date()
        let candidates = [WeakSpotCandidate(pattern: "uses 'more better'", category: .grammar)]
        let result = try merger.merge(
            candidates: candidates,
            sessionUserTurnIds: [UUID()],
            now: now
        )
        #expect(result.newlyCreated.count == 1)
        #expect(result.recurring.isEmpty)
        #expect(store.store.count == 1)
        #expect(store.store.values.first?.occurrenceCount == 1)
    }

    @Test func existingPatternIsIncremented() async throws {
        let store = InMemoryWeakSpotPersister()
        let now = Date()
        let existingId = UUID()
        try store.create(WeakSpot(
            id: existingId, pattern: "uses 'more better'", category: .grammar,
            firstSeen: now.addingTimeInterval(-86400), lastSeen: now.addingTimeInterval(-86400),
            occurrenceCount: 2, status: .active, exampleTurnIds: []
        ))
        let merger = WeakSpotMerger(persister: store)
        let candidates = [WeakSpotCandidate(pattern: "uses 'more better'", category: .grammar)]
        let exampleTurnId = UUID()
        let result = try merger.merge(
            candidates: candidates,
            sessionUserTurnIds: [exampleTurnId],
            now: now
        )
        #expect(result.newlyCreated.isEmpty)
        #expect(result.recurring.count == 1)
        let updated = try store.findByPattern("uses 'more better'")!
        #expect(updated.occurrenceCount == 3)
        #expect(updated.exampleTurnIds.contains(exampleTurnId))
    }

    @Test func mixOfNewAndRecurring() async throws {
        let store = InMemoryWeakSpotPersister()
        try store.create(WeakSpot(
            id: UUID(), pattern: "p-old", category: .grammar,
            firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 1, status: .active, exampleTurnIds: []
        ))
        let merger = WeakSpotMerger(persister: store)
        let candidates = [
            WeakSpotCandidate(pattern: "p-old", category: .grammar),
            WeakSpotCandidate(pattern: "p-new", category: .vocab),
        ]
        let result = try merger.merge(
            candidates: candidates,
            sessionUserTurnIds: [UUID()],
            now: Date()
        )
        #expect(result.newlyCreated.map(\.pattern) == ["p-new"])
        #expect(result.recurring.map(\.pattern) == ["p-old"])
    }

    @Test func emptyCandidatesReturnsEmptyResult() async throws {
        let store = InMemoryWeakSpotPersister()
        let merger = WeakSpotMerger(persister: store)
        let result = try merger.merge(candidates: [], sessionUserTurnIds: [], now: Date())
        #expect(result.newlyCreated.isEmpty)
        #expect(result.recurring.isEmpty)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter WeakSpotMergerTests
```

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/WeakSpotMerger.swift`:
```swift
import Foundation

public struct WeakSpotMergeResult: Equatable, Sendable {
    public let newlyCreated: [WeakSpot]
    public let recurring: [WeakSpot]
}

public struct WeakSpotMerger: Sendable {
    private let persister: WeakSpotPersisting

    public init(persister: WeakSpotPersisting) {
        self.persister = persister
    }

    /// `sessionUserTurnIds` is used for attaching example turn ids to weak spots —
    /// for v1 we attach the first user turn id of the session as a representative
    /// example. Cleaner per-pattern attachment is a future improvement.
    public func merge(
        candidates: [WeakSpotCandidate],
        sessionUserTurnIds: [UUID],
        now: Date
    ) throws -> WeakSpotMergeResult {
        var newlyCreated: [WeakSpot] = []
        var recurring: [WeakSpot] = []
        let exampleTurnId = sessionUserTurnIds.first

        for candidate in candidates {
            if let existing = try persister.findByPattern(candidate.pattern) {
                try persister.incrementOccurrence(
                    id: existing.id,
                    lastSeen: now,
                    addExampleTurnId: exampleTurnId
                )
                if let after = try persister.findByPattern(candidate.pattern) {
                    recurring.append(after)
                }
            } else {
                let ws = WeakSpot(
                    id: UUID(),
                    pattern: candidate.pattern,
                    category: candidate.category,
                    firstSeen: now,
                    lastSeen: now,
                    occurrenceCount: 1,
                    status: .active,
                    exampleTurnIds: exampleTurnId.map { [$0] } ?? []
                )
                try persister.create(ws)
                newlyCreated.append(ws)
            }
        }
        return WeakSpotMergeResult(newlyCreated: newlyCreated, recurring: recurring)
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter WeakSpotMergerTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 99 tests in 29 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/WeakSpotMerger.swift Tests/CoreTests/WeakSpotMergerTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add WeakSpotMerger (dedup candidates, upsert via persister)"
```

---

## Task 7 — `Debrief` value type + `CoachingEngine`

Pure-function composition of a `Debrief` from session, turns, metrics, and weak-spot results. No I/O.

**Files:**
- Create: `Sources/Core/Models/Debrief.swift`
- Create: `Sources/Core/Engine/CoachingEngine.swift`
- Create: `Tests/CoreTests/CoachingEngineTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/CoachingEngineTests.swift`:
```swift
import Testing
import Foundation
@testable import Core

@Suite struct CoachingEngineTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    private static func makeSession() -> Session {
        Session(
            id: UUID(), scenarioId: "test-01",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: Date(timeIntervalSince1970: 1_777_000_600),
            mode: .flow, status: .ended,
            summary: nil, personaSnapshot: "Test persona."
        )
    }

    @Test func includesSessionAndOneLineSummary() {
        let session = Self.makeSession()
        let metrics = SessionMetrics(
            userTurnCount: 4, totalWordCount: 60,
            totalFillerCount: 5, totalGrammarIssues: 3,
            averageUniqueWordRatio: 0.7, averageFillerDensity: 0.08
        )
        let debrief = CoachingEngine.compose(
            session: session,
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: []
        )
        #expect(debrief.session.id == session.id)
        #expect(!debrief.summary.isEmpty)
        #expect(debrief.sessionMetrics == metrics)
    }

    @Test func summaryReferencesScenarioTitleAndUserTurnCount() {
        let metrics = SessionMetrics(
            userTurnCount: 4, totalWordCount: 60,
            totalFillerCount: 5, totalGrammarIssues: 3,
            averageUniqueWordRatio: 0.7, averageFillerDensity: 0.08
        )
        let debrief = CoachingEngine.compose(
            session: Self.makeSession(),
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: []
        )
        #expect(debrief.summary.contains("Test"))
        #expect(debrief.summary.contains("4"))
    }

    @Test func suggestedDrillsTargetTopRecurringWeakSpots() {
        let now = Date()
        let recurring = [
            WeakSpot(id: UUID(), pattern: "uses 'more better'", category: .grammar,
                     firstSeen: now, lastSeen: now,
                     occurrenceCount: 5, status: .active, exampleTurnIds: []),
            WeakSpot(id: UUID(), pattern: "stutters on conditionals", category: .fluency,
                     firstSeen: now, lastSeen: now,
                     occurrenceCount: 3, status: .active, exampleTurnIds: []),
        ]
        let metrics = SessionMetrics(
            userTurnCount: 1, totalWordCount: 10, totalFillerCount: 0,
            totalGrammarIssues: 0, averageUniqueWordRatio: 1, averageFillerDensity: 0
        )
        let debrief = CoachingEngine.compose(
            session: Self.makeSession(),
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: [],
            recurringWeakSpots: recurring
        )
        #expect(debrief.suggestedDrills.count == 2)
        #expect(debrief.suggestedDrills[0].contains("more better"))
        #expect(debrief.suggestedDrills[1].contains("conditionals"))
    }

    @Test func splitsNewVsRecurringInOutput() {
        let now = Date()
        let newWS = [WeakSpot(id: UUID(), pattern: "p-new", category: .vocab,
                              firstSeen: now, lastSeen: now,
                              occurrenceCount: 1, status: .active, exampleTurnIds: [])]
        let recurringWS = [WeakSpot(id: UUID(), pattern: "p-old", category: .grammar,
                                    firstSeen: now, lastSeen: now,
                                    occurrenceCount: 3, status: .active, exampleTurnIds: [])]
        let metrics = SessionMetrics(
            userTurnCount: 1, totalWordCount: 5, totalFillerCount: 0,
            totalGrammarIssues: 0, averageUniqueWordRatio: 1, averageFillerDensity: 0
        )
        let debrief = CoachingEngine.compose(
            session: Self.makeSession(),
            scenario: Self.scenario,
            allTurns: [],
            sessionMetrics: metrics,
            newlyCreatedWeakSpots: newWS,
            recurringWeakSpots: recurringWS
        )
        #expect(debrief.newlyCreatedWeakSpots.map(\.pattern) == ["p-new"])
        #expect(debrief.recurringWeakSpots.map(\.pattern) == ["p-old"])
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter CoachingEngineTests
```

- [ ] **Step 3 — Implement `Debrief`**

`Sources/Core/Models/Debrief.swift`:
```swift
import Foundation

public struct Debrief: Equatable, Sendable {
    public let session: Session
    public let scenario: Scenario
    public let summary: String
    public let allTurns: [Turn]
    public let sessionMetrics: SessionMetrics
    public let newlyCreatedWeakSpots: [WeakSpot]
    public let recurringWeakSpots: [WeakSpot]
    public let suggestedDrills: [String]

    public init(
        session: Session,
        scenario: Scenario,
        summary: String,
        allTurns: [Turn],
        sessionMetrics: SessionMetrics,
        newlyCreatedWeakSpots: [WeakSpot],
        recurringWeakSpots: [WeakSpot],
        suggestedDrills: [String]
    ) {
        self.session = session
        self.scenario = scenario
        self.summary = summary
        self.allTurns = allTurns
        self.sessionMetrics = sessionMetrics
        self.newlyCreatedWeakSpots = newlyCreatedWeakSpots
        self.recurringWeakSpots = recurringWeakSpots
        self.suggestedDrills = suggestedDrills
    }
}
```

- [ ] **Step 4 — Implement `CoachingEngine`**

`Sources/Core/Engine/CoachingEngine.swift`:
```swift
import Foundation

public enum CoachingEngine {
    public static func compose(
        session: Session,
        scenario: Scenario,
        allTurns: [Turn],
        sessionMetrics: SessionMetrics,
        newlyCreatedWeakSpots: [WeakSpot],
        recurringWeakSpots: [WeakSpot]
    ) -> Debrief {
        let summary = makeSummary(scenario: scenario, metrics: sessionMetrics)
        let drills = makeDrills(recurringWeakSpots: recurringWeakSpots,
                                newlyCreatedWeakSpots: newlyCreatedWeakSpots)
        return Debrief(
            session: session,
            scenario: scenario,
            summary: summary,
            allTurns: allTurns,
            sessionMetrics: sessionMetrics,
            newlyCreatedWeakSpots: newlyCreatedWeakSpots,
            recurringWeakSpots: recurringWeakSpots,
            suggestedDrills: drills
        )
    }

    private static func makeSummary(scenario: Scenario, metrics: SessionMetrics) -> String {
        let n = metrics.userTurnCount
        let issues = metrics.totalGrammarIssues
        return "Practiced '\(scenario.title)' across \(n) user turn\(n == 1 ? "" : "s"); \(issues) clear grammar slip\(issues == 1 ? "" : "s") flagged."
    }

    private static func makeDrills(recurringWeakSpots: [WeakSpot], newlyCreatedWeakSpots: [WeakSpot]) -> [String] {
        let top = recurringWeakSpots
            .sorted { $0.occurrenceCount > $1.occurrenceCount }
            .prefix(3)
        return top.map { "Drill: \($0.pattern)" }
    }
}
```

- [ ] **Step 5 — Confirm green**

```bash
bin/test.sh --filter CoachingEngineTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 103 tests in 30 suites) all green.

- [ ] **Step 6 — Commit**

```bash
git add Sources/Core/Models/Debrief.swift Sources/Core/Engine/CoachingEngine.swift Tests/CoreTests/CoachingEngineTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add Debrief + CoachingEngine for post-session analysis"
```

---

## Task 8 — `SessionAnalyzer`

The top-level orchestrator that takes a session id, fetches its turns from `TurnPersisting`, runs `MetricsAnalyzer`, runs `WeakSpotExtractor` over the user transcript, runs `WeakSpotMerger`, and returns a `Debrief` via `CoachingEngine`.

**Files:**
- Create: `Sources/Core/Engine/SessionAnalyzer.swift`
- Create: `Tests/CoreTests/SessionAnalyzerTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/SessionAnalyzerTests.swift`:
```swift
import Testing
import Foundation
import Core
import Fakes
@testable import Core

@Suite struct SessionAnalyzerTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.", openingLine: "Hi.",
        difficulty: 2, tags: [], notes: nil
    )

    final class FakeSessionPersister: SessionPersisting, @unchecked Sendable {
        var sessions: [UUID: Session] = [:]
        func create(_ session: Session) throws { sessions[session.id] = session }
        func find(id: UUID) throws -> Session? { sessions[id] }
        func finalize(id: UUID, endedAt: Date, summary: String?) throws {}
        func listActive() throws -> [Session] { Array(sessions.values) }
    }

    final class FakeTurnPersister: TurnPersisting, @unchecked Sendable {
        var turns: [Turn] = []
        var stored: [(turnId: UUID, json: String)] = []
        func append(_ turn: Turn) throws { turns.append(turn) }
        func list(forSession sessionId: UUID) throws -> [Turn] {
            turns.filter { $0.sessionId == sessionId }.sorted { $0.turnIndex < $1.turnIndex }
        }
        func markIncomplete(id: UUID) throws {}
        func updateMetricsJson(turnId: UUID, json: String) throws {
            stored.append((turnId, json))
        }
    }

    final class FakeWeakSpotPersister: WeakSpotPersisting, @unchecked Sendable {
        var store: [UUID: WeakSpot] = [:]
        func listActiveByFrequency(limit: Int) throws -> [WeakSpot] { Array(store.values).prefix(limit).map { $0 } }
        func create(_ ws: WeakSpot) throws { store[ws.id] = ws }
        func findByPattern(_ pattern: String) throws -> WeakSpot? {
            store.values.first { $0.pattern == pattern }
        }
        func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
            guard var ws = store[id] else { return }
            ws.occurrenceCount += 1; ws.lastSeen = lastSeen
            if let t = addExampleTurnId, !ws.exampleTurnIds.contains(t) {
                ws.exampleTurnIds.append(t)
            }
            store[id] = ws
        }
    }

    @Test func endToEndAnalysisProducesDebriefWithMetricsAndWeakSpots() async throws {
        let sessionPersister = FakeSessionPersister()
        let turnPersister = FakeTurnPersister()
        let weakSpotPersister = FakeWeakSpotPersister()
        let session = Session(
            id: UUID(), scenarioId: "test-01",
            startedAt: Date(), endedAt: Date(),
            mode: .flow, status: .ended,
            summary: nil, personaSnapshot: "Test persona."
        )
        try sessionPersister.create(session)
        try turnPersister.append(Turn(
            id: UUID(), sessionId: session.id, turnIndex: 0, speaker: .ai,
            text: "Hi.", audioPath: nil, startedAt: Date(),
            durationMs: 0, metricsJson: nil, isComplete: true
        ))
        try turnPersister.append(Turn(
            id: UUID(), sessionId: session.id, turnIndex: 1, speaker: .user,
            text: "Um, I have finish the report yesterday.", audioPath: nil,
            startedAt: Date(), durationMs: 0, metricsJson: nil, isComplete: true
        ))
        try turnPersister.append(Turn(
            id: UUID(), sessionId: session.id, turnIndex: 2, speaker: .user,
            text: "I goes to office every day.", audioPath: nil,
            startedAt: Date(), durationMs: 0, metricsJson: nil, isComplete: true
        ))

        // GrammarJudge will be called twice (one per user turn). Then
        // WeakSpotExtractor is called once over the joined transcript.
        let llm = FakeLLMProvider(scriptedReplyBatches: [
            ["{\"grammarIssueCount\": 2}"],          // user turn 1 grammar count
            ["{\"grammarIssueCount\": 1}"],          // user turn 2 grammar count
            ["{\"patterns\":[{\"pattern\":\"present-perfect with past time\",\"category\":\"grammar\"}]}"],  // weak spots
        ])

        let analyzer = SessionAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotExtractor: WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotMerger: WeakSpotMerger(persister: weakSpotPersister),
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            scenarioCatalog: try ScenarioCatalog.loadBuiltIn()
        )

        // The scenarioCatalog won't have "test-01" — analyzer should use a fallback
        // scenario constructed from session.personaSnapshot.

        let debrief = try await analyzer.analyze(sessionId: session.id)
        #expect(debrief.session.id == session.id)
        #expect(debrief.sessionMetrics.userTurnCount == 2)
        #expect(debrief.sessionMetrics.totalGrammarIssues == 3)
        #expect(debrief.newlyCreatedWeakSpots.count == 1)
        #expect(debrief.newlyCreatedWeakSpots[0].pattern == "present-perfect with past time")
        #expect(debrief.recurringWeakSpots.isEmpty)
        #expect(turnPersister.stored.count == 2) // metrics persisted for 2 user turns
    }

    @Test func missingSessionThrows() async throws {
        let llm = FakeLLMProvider(scriptedReplies: ["{}"])
        let analyzer = SessionAnalyzer(
            grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotExtractor: WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake")),
            weakSpotMerger: WeakSpotMerger(persister: FakeWeakSpotPersister()),
            sessionPersister: FakeSessionPersister(),
            turnPersister: FakeTurnPersister(),
            scenarioCatalog: try ScenarioCatalog.loadBuiltIn()
        )
        await #expect(throws: SessionAnalyzerError.self) {
            _ = try await analyzer.analyze(sessionId: UUID())
        }
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter SessionAnalyzerTests
```

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/SessionAnalyzer.swift`:
```swift
import Foundation

public struct SessionAnalyzer: Sendable {
    private let grammarJudge: GrammarJudge
    private let weakSpotExtractor: WeakSpotExtractor
    private let weakSpotMerger: WeakSpotMerger
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting
    private let scenarioCatalog: ScenarioCatalog

    public init(
        grammarJudge: GrammarJudge,
        weakSpotExtractor: WeakSpotExtractor,
        weakSpotMerger: WeakSpotMerger,
        sessionPersister: SessionPersisting,
        turnPersister: TurnPersisting,
        scenarioCatalog: ScenarioCatalog
    ) {
        self.grammarJudge = grammarJudge
        self.weakSpotExtractor = weakSpotExtractor
        self.weakSpotMerger = weakSpotMerger
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.scenarioCatalog = scenarioCatalog
    }

    public func analyze(sessionId: UUID) async throws -> Debrief {
        guard let session = try sessionPersister.find(id: sessionId) else {
            throw SessionAnalyzerError.sessionNotFound(sessionId)
        }
        let turns = try turnPersister.list(forSession: sessionId)

        let metricsAnalyzer = MetricsAnalyzer(grammarJudge: grammarJudge, turnPersister: turnPersister)
        let sessionMetrics = await metricsAnalyzer.analyze(turns: turns)

        let userTranscript = turns
            .filter { $0.speaker == .user && $0.isComplete }
            .map(\.text)
            .joined(separator: "\n")
        let candidates = try await weakSpotExtractor.extract(fromUserTranscript: userTranscript)
        let userTurnIds = turns.filter { $0.speaker == .user }.map(\.id)
        let mergeResult = try weakSpotMerger.merge(
            candidates: candidates,
            sessionUserTurnIds: userTurnIds,
            now: Date()
        )

        // Resolve scenario: try the catalog first (for built-ins), fall back to
        // a synthetic scenario reconstructed from the session's personaSnapshot.
        let scenario = scenarioCatalog.scenario(id: session.scenarioId) ?? Scenario(
            id: session.scenarioId,
            source: .custom,
            title: session.scenarioId,
            domain: .work,
            persona: session.personaSnapshot,
            openingLine: "",
            difficulty: 2,
            tags: [],
            notes: nil
        )

        return CoachingEngine.compose(
            session: session,
            scenario: scenario,
            allTurns: turns,
            sessionMetrics: sessionMetrics,
            newlyCreatedWeakSpots: mergeResult.newlyCreated,
            recurringWeakSpots: mergeResult.recurring
        )
    }
}

public enum SessionAnalyzerError: Error, Equatable {
    case sessionNotFound(UUID)
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter SessionAnalyzerTests
bin/test.sh
```

Expected: 2 new tests pass; full suite (now 105 tests in 31 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/SessionAnalyzer.swift Tests/CoreTests/SessionAnalyzerTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add SessionAnalyzer (top-level analysis orchestrator)"
```

---

## Task 9 — SmokeCLI: extend with end-of-session analysis

After the engine demo finishes a session, run `SessionAnalyzer` on it and print the debrief.

**Files:**
- Modify: `Sources/SmokeCLI/main.swift`

- [ ] **Step 1 — Replace `main.swift`**

`Sources/SmokeCLI/main.swift`:
```swift
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
    let weakSpotRepo = WeakSpotRepository(database: db)

    // LLM script:
    //   batch 0: AI reply for user turn 1
    //   batch 1: AI reply for user turn 2
    //   batch 2: GrammarJudge for user turn 1
    //   batch 3: GrammarJudge for user turn 2
    //   batch 4: WeakSpotExtractor over the joined transcript
    let llm = FakeLLMProvider(scriptedReplyBatches: [
        ["I see — auth refactor done. ", "Any blockers I should know about?"],
        ["Got it. Let's plan the review for after standup."],
        ["{\"grammarIssueCount\": 1}"],
        ["{\"grammarIssueCount\": 0}"],
        ["{\"patterns\":[{\"pattern\":\"uses passive 'I'd like a review' instead of asking directly\",\"category\":\"vocab\"}]}"],
    ])
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
    print("→ User turn 1"); _ = try await engine.runUserTurn()
    print("→ User turn 2"); _ = try await engine.runUserTurn()
    print("→ Ending session")
    try await engine.end(summary: "Standup practice via fakes.")

    let session = (try await engine.sessionForTesting())!

    print("→ Running post-session analysis")
    let analyzer = SessionAnalyzer(
        grammarJudge: GrammarJudge(llm: llm, options: LLMOptions(modelName: "fake-llm")),
        weakSpotExtractor: WeakSpotExtractor(llm: llm, options: LLMOptions(modelName: "fake-llm")),
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
}

do {
    try await main()
    print("\n✓ analysis smoke OK")
} catch {
    print("\n✗ analysis smoke FAILED: \(error)")
    exit(1)
}
```

- [ ] **Step 2 — Build and run**

```bash
swift build
swift run smoke-cli
```

Expected output (approximate):
```
→ Opening DB at /tmp/eng-assistant-engine-smoke.sqlite
→ Loading scenario
  scenario: Daily Engineering Standup
→ Starting session
→ User turn 1
→ User turn 2
→ Ending session
→ Running post-session analysis

=== Debrief ===
Summary: Practiced 'Daily Engineering Standup' across 2 user turns; 1 clear grammar slip flagged.
Session metrics:
  user turns: 2
  total words: <some number>
  fillers: <some number>
  grammar issues: 1
  avg unique-word ratio: 0.<value>
  avg filler density: 0.<value>
New weak spots:
  + uses passive 'I'd like a review' instead of asking directly (vocab)

✓ analysis smoke OK
```

Verify exit code 0.

- [ ] **Step 3 — Run full test suite**

```bash
bin/test.sh 2>&1 | tail -3
```

Expected: 105 tests in 31 suites, all green.

- [ ] **Step 4 — Commit**

```bash
git add Sources/SmokeCLI/main.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(smoke): extend CLI with end-of-session analysis + debrief printout"
```

---

## Plan 3 Self-Review

| Spec section / requirement | Covered by |
|---|---|
| `MetricsAnalyzer` (heuristic + LLM-as-judge for grammar) | Tasks 2-4 |
| Per-turn `metrics_json` persistence | Task 4 (via `turnPersister.updateMetricsJson`) |
| `WeakSpotExtractor` (LLM, recurring patterns) | Task 5 |
| Dedup against existing weak_spots, upsert occurrence | Task 6 |
| `CoachingEngine` (debrief: summary, highlights, drills) | Task 7 |
| End-to-end orchestrator | Task 8 |
| End-to-end demo | Task 9 |

**Out of scope (deferred):**
- Real local LLM (Ollama) — Plan 4
- Real audio (Whisper STT, Piper TTS, AVAudio capture) — Plans 4-5
- WPM and pause-ratio metrics (need real audio durations) — Plan 5
- Daily metrics rollup into `metrics_daily` table — defer until UI/dashboard work in Plan 6 (the rollup logic is trivial; gate it on actually rendering it)
- Transcript markdown mirror — Plan 6
- Fuzzy weak-spot pattern matching — future improvement

---

## Definition of Done (Plan 3)

- `swift build` succeeds with no warnings.
- `bin/test.sh` runs ~105 tests across ~31 suites and they all pass.
- `swift run smoke-cli` produces the engine + analysis demo and exits 0.
- One git commit per task (9 commits) on `main`.
- No file-internal placeholders, TODOs, or unfinished functions.
- `Core` still has zero dependency on `Persistence`/AppKit/SwiftUI/GRDB.
