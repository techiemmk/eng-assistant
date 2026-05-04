# Foundation & Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a Swift Package workspace with a `Core` module (domain types + scenario catalog) and a `Persistence` module (GRDB-backed SQLite with full schema and repositories). End state: every model, repository, and the scenario catalog is unit-tested; a CLI smoke test creates a session, appends turns, and reads them back.

**Architecture:** Pure SPM workspace (no Xcode project yet — that comes in Plan 6). Two SPM library modules, one CLI executable for smoke testing. `Core` defines value types and pure business logic with no dependency on AppKit/SwiftUI/GRDB. `Persistence` depends on `Core` and wraps GRDB. Tests use in-memory SQLite for speed and isolation.

**Tech Stack:** Swift 5.9+, Swift Package Manager, GRDB.swift 6.x, **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`).

**Testing convention:** This project uses **Swift Testing** (the modern Swift-native test framework that ships with the toolchain) rather than XCTest. XCTest requires a full Xcode install; Swift Testing works with just the Command Line Tools. All test code blocks in this plan should be read through that lens — translate any `XCTAssert*`/`XCTestCase` you may see in older docs to the equivalent `#expect`/`#require` and `@Test`/`@Suite` constructs:

| XCTest | Swift Testing |
|---|---|
| `import XCTest` | `import Testing` |
| `final class FooTests: XCTestCase { func testBar() { ... } }` | `@Suite struct FooTests { @Test func bar() { ... } }` (or top-level `@Test func`) |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(x)` | `#expect(x)` |
| `XCTAssertFalse(x)` | `#expect(!x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertNotNil(x)` | `#expect(x != nil)` |
| `XCTAssertGreaterThanOrEqual(a, b)` | `#expect(a >= b)` |
| `func testFoo() throws` | `@Test func foo() throws` |
| `try XCTUnwrap(x)` | `try #require(x)` |
| `XCTAssertThrowsError { ... }` | `#expect(throws: SomeError.self) { ... }` |
| `swift test --filter FooTests.testBar` | `swift test --filter FooTests/bar` |

The implementer subagents will be dispatched with task text where this conversion has already been applied.

---

## File Structure

```
eng-assistant/
├── Package.swift                                    # SPM workspace root
├── Sources/
│   ├── Core/                                        # Domain types + catalog
│   │   ├── Models/
│   │   │   ├── Scenario.swift
│   │   │   ├── Session.swift
│   │   │   ├── Turn.swift
│   │   │   ├── WeakSpot.swift
│   │   │   ├── Metrics.swift
│   │   │   └── Settings.swift
│   │   ├── ScenarioCatalog.swift
│   │   └── Resources/
│   │       └── built-in-scenarios.json
│   ├── Persistence/                                 # GRDB layer
│   │   ├── Database.swift
│   │   ├── Migrations.swift
│   │   ├── StorageLayout.swift
│   │   └── Repositories/
│   │       ├── SessionRepository.swift
│   │       ├── TurnRepository.swift
│   │       ├── ScenarioRepository.swift
│   │       ├── WeakSpotRepository.swift
│   │       ├── MetricsRepository.swift
│   │       └── SettingsRepository.swift
│   └── SmokeCLI/                                    # Hand-runnable verifier
│       └── main.swift
└── Tests/
    ├── CoreTests/
    │   ├── ModelsTests.swift
    │   └── ScenarioCatalogTests.swift
    └── PersistenceTests/
        ├── DatabaseTests.swift
        ├── MigrationsTests.swift
        ├── SessionRepositoryTests.swift
        ├── TurnRepositoryTests.swift
        ├── ScenarioRepositoryTests.swift
        ├── WeakSpotRepositoryTests.swift
        ├── MetricsRepositoryTests.swift
        ├── SettingsRepositoryTests.swift
        └── StorageLayoutTests.swift
```

**Per-file responsibility:**

| File | Responsibility |
|---|---|
| `Package.swift` | Workspace definition: `Core` lib, `Persistence` lib (depends on Core + GRDB), `SmokeCLI` exe (depends on both). |
| `Models/*.swift` | Plain value types: `Scenario`, `Session`, `Turn`, `WeakSpot`, etc. `Codable`, `Equatable`, no logic. |
| `ScenarioCatalog.swift` | Loads built-in JSON from `Bundle.module`, exposes filtering by domain/tag/difficulty. Pure Core. |
| `built-in-scenarios.json` | Initial 6 scenarios (2 per domain). Grows in Plan 6. |
| `Database.swift` | Thin wrapper around `DatabaseQueue` / `DatabasePool`. Opens DB file, runs migrations on init. |
| `Migrations.swift` | Versioned GRDB migrations. v1 creates all tables. |
| `StorageLayout.swift` | Resolves filesystem paths under `~/Library/Application Support/EngAssistant/`. |
| `Repositories/*.swift` | One file per table. Each owns CRUD + table-specific queries. |
| `SmokeCLI/main.swift` | Hand-runnable: opens DB at `/tmp/eng-assistant-smoke.sqlite`, creates a session, appends turns, lists results. Verifies the stack works on a real machine. |

---

## Task Decomposition Notes

- TDD throughout. Every functional task is **failing test → run (red) → minimal impl → run (green) → commit**.
- Each commit follows conventional commit prefixes: `chore:`, `feat:`, `test:`. Use `feat:` when the test+impl together add user-visible behavior; `chore:` for scaffolding.
- All `swift test` invocations should pass before each commit.
- Tests use in-memory SQLite (`DatabaseQueue()`) so they're fast and need no cleanup.

---

## Task 1: Initialize SPM workspace

**Files:**
- Create: `Package.swift`
- Create: `Sources/Core/Placeholder.swift`
- Create: `Sources/Persistence/Placeholder.swift`
- Create: `Sources/SmokeCLI/main.swift`
- Create: `Tests/CoreTests/PlaceholderTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.DS_Store
.build/
.swiftpm/
*.xcodeproj
Package.resolved
.superpowers/
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .executable(name: "smoke-cli", targets: ["SmokeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "Core",
            resources: [.process("Resources")]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "SmokeCLI",
            dependencies: ["Core", "Persistence"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
```

- [ ] **Step 3: Write placeholder source files so the package builds**

`Sources/Core/Placeholder.swift`:
```swift
public enum CoreModule {
    public static let version = "0.1.0"
}
```

`Sources/Persistence/Placeholder.swift`:
```swift
import Core

public enum PersistenceModule {
    public static let version = Core.CoreModule.version
}
```

`Sources/SmokeCLI/main.swift`:
```swift
import Core
import Persistence

print("EngAssistant smoke CLI — Core \(CoreModule.version), Persistence \(PersistenceModule.version)")
```

`Sources/Core/Resources/.gitkeep`: (empty file so the resources dir exists)

`Tests/CoreTests/PlaceholderTests.swift`:
```swift
import XCTest
@testable import Core

final class PlaceholderTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertFalse(CoreModule.version.isEmpty)
    }
}
```

- [ ] **Step 4: Build and run tests**

```bash
swift build
swift test
```

Expected: build succeeds; `PlaceholderTests.testVersionPresent` passes.

- [ ] **Step 5: Run the smoke CLI**

```bash
swift run smoke-cli
```

Expected: prints `EngAssistant smoke CLI — Core 0.1.0, Persistence 0.1.0`

- [ ] **Step 6: Commit**

```bash
git add .
git commit -m "chore: initialize SPM workspace with Core, Persistence, SmokeCLI"
```

---

## Task 2: Domain enums & `Scenario` model

**Files:**
- Create: `Sources/Core/Models/Scenario.swift`
- Create: `Tests/CoreTests/ModelsTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/ModelsTests.swift`:
```swift
import XCTest
@testable import Core

final class ScenarioTests: XCTestCase {
    func testScenarioCodableRoundTrip() throws {
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
        XCTAssertEqual(original, decoded)
    }

    func testScenarioDomainCases() {
        XCTAssertEqual(ScenarioDomain.allCases.count, 3)
        XCTAssertTrue(ScenarioDomain.allCases.contains(.work))
        XCTAssertTrue(ScenarioDomain.allCases.contains(.networking))
        XCTAssertTrue(ScenarioDomain.allCases.contains(.social))
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter CoreTests.ScenarioTests
```

Expected: compile error — `Scenario`, `ScenarioDomain`, `ScenarioSource` not found.

- [ ] **Step 3: Implement `Scenario`**

`Sources/Core/Models/Scenario.swift`:
```swift
import Foundation

public enum ScenarioSource: String, Codable, Equatable, Sendable {
    case builtin
    case custom
}

public enum ScenarioDomain: String, Codable, Equatable, Sendable, CaseIterable {
    case work
    case networking
    case social
}

public struct Scenario: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: ScenarioSource
    public let title: String
    public let domain: ScenarioDomain
    public let persona: String
    public let openingLine: String
    public let difficulty: Int     // 1..5
    public let tags: [String]
    public let notes: String?

    public init(
        id: String,
        source: ScenarioSource,
        title: String,
        domain: ScenarioDomain,
        persona: String,
        openingLine: String,
        difficulty: Int,
        tags: [String],
        notes: String?
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.domain = domain
        self.persona = persona
        self.openingLine = openingLine
        self.difficulty = difficulty
        self.tags = tags
        self.notes = notes
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter CoreTests.ScenarioTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/Scenario.swift Tests/CoreTests/ModelsTests.swift
git commit -m "feat(core): add Scenario, ScenarioDomain, ScenarioSource"
```

---

## Task 3: `Session` model with mode + status enums

**Files:**
- Create: `Sources/Core/Models/Session.swift`
- Modify: `Tests/CoreTests/ModelsTests.swift`

- [ ] **Step 1: Append failing tests**

Append to `Tests/CoreTests/ModelsTests.swift`:
```swift
final class SessionTests: XCTestCase {
    func testSessionCodableRoundTrip() throws {
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
        XCTAssertEqual(session, decoded)
    }

    func testSessionModeRawValues() {
        XCTAssertEqual(SessionMode.flow.rawValue, "flow")
        XCTAssertEqual(SessionMode.coach.rawValue, "coach")
    }

    func testSessionStatusRawValues() {
        XCTAssertEqual(SessionStatus.active.rawValue, "active")
        XCTAssertEqual(SessionStatus.ended.rawValue, "ended")
        XCTAssertEqual(SessionStatus.abandoned.rawValue, "abandoned")
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter CoreTests.SessionTests
```

Expected: compile error — `Session`, `SessionMode`, `SessionStatus` not found.

- [ ] **Step 3: Implement `Session`**

`Sources/Core/Models/Session.swift`:
```swift
import Foundation

public enum SessionMode: String, Codable, Equatable, Sendable, CaseIterable {
    case flow
    case coach
}

public enum SessionStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case active     // started but not ended
    case ended      // user ended cleanly
    case abandoned  // detected on next launch as orphaned and dismissed
}

public struct Session: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let scenarioId: String
    public let startedAt: Date
    public var endedAt: Date?
    public let mode: SessionMode
    public var status: SessionStatus
    public var summary: String?
    public let personaSnapshot: String

    public init(
        id: UUID,
        scenarioId: String,
        startedAt: Date,
        endedAt: Date?,
        mode: SessionMode,
        status: SessionStatus,
        summary: String?,
        personaSnapshot: String
    ) {
        self.id = id
        self.scenarioId = scenarioId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.status = status
        self.summary = summary
        self.personaSnapshot = personaSnapshot
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter CoreTests.SessionTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/Session.swift Tests/CoreTests/ModelsTests.swift
git commit -m "feat(core): add Session, SessionMode, SessionStatus"
```

---

## Task 4: `Turn` model

**Files:**
- Create: `Sources/Core/Models/Turn.swift`
- Modify: `Tests/CoreTests/ModelsTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
final class TurnTests: XCTestCase {
    func testTurnCodableRoundTrip() throws {
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
        XCTAssertEqual(turn, decoded)
    }

    func testSpeakerRawValues() {
        XCTAssertEqual(Speaker.user.rawValue, "user")
        XCTAssertEqual(Speaker.ai.rawValue, "ai")
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter CoreTests.TurnTests
```

Expected: compile error — `Turn`, `Speaker` not found.

- [ ] **Step 3: Implement `Turn`**

`Sources/Core/Models/Turn.swift`:
```swift
import Foundation

public enum Speaker: String, Codable, Equatable, Sendable {
    case user
    case ai
}

public struct Turn: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: UUID
    public let turnIndex: Int
    public let speaker: Speaker
    public var text: String
    public var audioPath: String?
    public let startedAt: Date
    public var durationMs: Int
    public var metricsJson: String?
    public var isComplete: Bool

    public init(
        id: UUID,
        sessionId: UUID,
        turnIndex: Int,
        speaker: Speaker,
        text: String,
        audioPath: String?,
        startedAt: Date,
        durationMs: Int,
        metricsJson: String?,
        isComplete: Bool
    ) {
        self.id = id
        self.sessionId = sessionId
        self.turnIndex = turnIndex
        self.speaker = speaker
        self.text = text
        self.audioPath = audioPath
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.metricsJson = metricsJson
        self.isComplete = isComplete
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter CoreTests.TurnTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/Turn.swift Tests/CoreTests/ModelsTests.swift
git commit -m "feat(core): add Turn, Speaker"
```

---

## Task 5: `WeakSpot` model

**Files:**
- Create: `Sources/Core/Models/WeakSpot.swift`
- Modify: `Tests/CoreTests/ModelsTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
final class WeakSpotTests: XCTestCase {
    func testWeakSpotCodableRoundTrip() throws {
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
        XCTAssertEqual(ws, decoded)
    }

    func testWeakSpotCategoryCases() {
        XCTAssertEqual(WeakSpotCategory.allCases.count, 4)
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter CoreTests.WeakSpotTests
```

Expected: compile error.

- [ ] **Step 3: Implement `WeakSpot`**

`Sources/Core/Models/WeakSpot.swift`:
```swift
import Foundation

public enum WeakSpotCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case grammar
    case vocab
    case filler
    case fluency
}

public enum WeakSpotStatus: String, Codable, Equatable, Sendable {
    case active
    case resolved
}

public struct WeakSpot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var pattern: String
    public var category: WeakSpotCategory
    public var firstSeen: Date
    public var lastSeen: Date
    public var occurrenceCount: Int
    public var status: WeakSpotStatus
    public var exampleTurnIds: [UUID]

    public init(
        id: UUID,
        pattern: String,
        category: WeakSpotCategory,
        firstSeen: Date,
        lastSeen: Date,
        occurrenceCount: Int,
        status: WeakSpotStatus,
        exampleTurnIds: [UUID]
    ) {
        self.id = id
        self.pattern = pattern
        self.category = category
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.occurrenceCount = occurrenceCount
        self.status = status
        self.exampleTurnIds = exampleTurnIds
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter CoreTests.WeakSpotTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/WeakSpot.swift Tests/CoreTests/ModelsTests.swift
git commit -m "feat(core): add WeakSpot, WeakSpotCategory, WeakSpotStatus"
```

---

## Task 6: `Metrics` & `Settings` models

**Files:**
- Create: `Sources/Core/Models/Metrics.swift`
- Create: `Sources/Core/Models/Settings.swift`
- Modify: `Tests/CoreTests/ModelsTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
final class MetricsTests: XCTestCase {
    func testTurnMetricsCodableRoundTrip() throws {
        let m = TurnMetrics(
            wordsPerMinute: 132.5,
            pauseRatio: 0.18,
            fillerCount: 4,
            uniqueWordRatio: 0.72,
            grammarIssueCount: 1
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(TurnMetrics.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    func testDailyMetricsCodableRoundTrip() throws {
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
        XCTAssertEqual(m, decoded)
    }
}

final class AppSettingsKeyTests: XCTestCase {
    func testKnownKeysPresent() {
        XCTAssertEqual(AppSettingKey.defaultMode.rawValue, "default_mode")
        XCTAssertEqual(AppSettingKey.audioRetentionDays.rawValue, "audio_retention_days")
        XCTAssertEqual(AppSettingKey.vadSensitivity.rawValue, "vad_sensitivity")
        XCTAssertEqual(AppSettingKey.llmModelName.rawValue, "llm_model_name")
        XCTAssertEqual(AppSettingKey.ttsVoiceName.rawValue, "tts_voice_name")
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter CoreTests
```

Expected: compile errors for `TurnMetrics`, `DailyMetrics`, `AppSettingKey`.

- [ ] **Step 3: Implement metrics**

`Sources/Core/Models/Metrics.swift`:
```swift
import Foundation

public struct TurnMetrics: Codable, Equatable, Sendable {
    public var wordsPerMinute: Double
    public var pauseRatio: Double          // 0..1
    public var fillerCount: Int
    public var uniqueWordRatio: Double     // unique / total
    public var grammarIssueCount: Int

    public init(
        wordsPerMinute: Double,
        pauseRatio: Double,
        fillerCount: Int,
        uniqueWordRatio: Double,
        grammarIssueCount: Int
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.pauseRatio = pauseRatio
        self.fillerCount = fillerCount
        self.uniqueWordRatio = uniqueWordRatio
        self.grammarIssueCount = grammarIssueCount
    }
}

public struct DailyMetrics: Codable, Equatable, Sendable {
    public let date: String                // ISO yyyy-MM-dd
    public var totalMinutes: Int
    public var sessionsCount: Int
    public var avgFluency: Double
    public var avgVocabRange: Double
    public var avgFillerDensity: Double
    public var avgGrammarSlipsPerMin: Double

    public init(
        date: String,
        totalMinutes: Int,
        sessionsCount: Int,
        avgFluency: Double,
        avgVocabRange: Double,
        avgFillerDensity: Double,
        avgGrammarSlipsPerMin: Double
    ) {
        self.date = date
        self.totalMinutes = totalMinutes
        self.sessionsCount = sessionsCount
        self.avgFluency = avgFluency
        self.avgVocabRange = avgVocabRange
        self.avgFillerDensity = avgFillerDensity
        self.avgGrammarSlipsPerMin = avgGrammarSlipsPerMin
    }
}
```

- [ ] **Step 4: Implement settings keys**

`Sources/Core/Models/Settings.swift`:
```swift
import Foundation

public enum AppSettingKey: String, CaseIterable, Sendable {
    case defaultMode = "default_mode"
    case audioRetentionDays = "audio_retention_days"
    case vadSensitivity = "vad_sensitivity"
    case llmModelName = "llm_model_name"
    case ttsVoiceName = "tts_voice_name"
    case sttModelName = "stt_model_name"
}
```

- [ ] **Step 5: Run tests, confirm pass**

```bash
swift test --filter CoreTests
```

Expected: all model tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Models/Metrics.swift Sources/Core/Models/Settings.swift Tests/CoreTests/ModelsTests.swift
git commit -m "feat(core): add TurnMetrics, DailyMetrics, AppSettingKey"
```

---

## Task 7: Built-in scenarios JSON & catalog loader

**Files:**
- Create: `Sources/Core/Resources/built-in-scenarios.json`
- Create: `Sources/Core/ScenarioCatalog.swift`
- Create: `Tests/CoreTests/ScenarioCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/ScenarioCatalogTests.swift`:
```swift
import XCTest
@testable import Core

final class ScenarioCatalogTests: XCTestCase {
    func testLoadsBundledScenarios() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        XCTAssertGreaterThanOrEqual(catalog.allScenarios.count, 6)
    }

    func testEachDomainHasAtLeastTwoScenarios() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        for domain in ScenarioDomain.allCases {
            let count = catalog.scenarios(in: domain).count
            XCTAssertGreaterThanOrEqual(count, 2, "domain \(domain) has only \(count)")
        }
    }

    func testFilterByTag() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        let meeting = catalog.scenarios(withTag: "meeting")
        XCTAssertFalse(meeting.isEmpty)
        XCTAssertTrue(meeting.allSatisfy { $0.tags.contains("meeting") })
    }

    func testAllScenariosHaveBuiltinSource() throws {
        let catalog = try ScenarioCatalog.loadBuiltIn()
        XCTAssertTrue(catalog.allScenarios.allSatisfy { $0.source == .builtin })
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter CoreTests.ScenarioCatalogTests
```

Expected: compile error — `ScenarioCatalog` not found.

- [ ] **Step 3: Author built-in scenarios JSON**

`Sources/Core/Resources/built-in-scenarios.json`:
```json
[
  {
    "id": "work-standup-01",
    "source": "builtin",
    "title": "Daily Engineering Standup",
    "domain": "work",
    "persona": "A no-nonsense engineering manager named Priya. Friendly but time-pressed. Asks pointed follow-up questions about blockers.",
    "openingLine": "Good morning. What did you finish yesterday, and what are you picking up today?",
    "difficulty": 2,
    "tags": ["meeting", "team", "status"],
    "notes": null
  },
  {
    "id": "work-1on1-01",
    "source": "builtin",
    "title": "Skip-level 1:1 with VP",
    "domain": "work",
    "persona": "A skip-level VP named David. Warm, curious, asks about your career growth and frustrations. Will probe gently if you give vague answers.",
    "openingLine": "Thanks for making time. How's the work been going for you these past few weeks — really?",
    "difficulty": 3,
    "tags": ["1on1", "career", "leadership"],
    "notes": null
  },
  {
    "id": "networking-conf-01",
    "source": "builtin",
    "title": "Conference Coffee Break",
    "domain": "networking",
    "persona": "A senior engineer at another company named Sam, met in line at a conference coffee station. Polite, mildly introverted, easy to lose if you don't keep the thread going.",
    "openingLine": "Oh hey — long line. Are you here for the whole conference or just today?",
    "difficulty": 2,
    "tags": ["conference", "smalltalk", "intro"],
    "notes": null
  },
  {
    "id": "networking-intro-01",
    "source": "builtin",
    "title": "New Team Member Intro",
    "domain": "networking",
    "persona": "A new colleague named Aisha who just joined another team. Friendly, asks open-ended questions, looking to find common ground.",
    "openingLine": "Hi! I just joined the platform team last week — how long have you been here?",
    "difficulty": 1,
    "tags": ["intro", "smalltalk", "colleague"],
    "notes": null
  },
  {
    "id": "social-dinner-01",
    "source": "builtin",
    "title": "Dinner with Friends",
    "domain": "social",
    "persona": "A close friend named Alex catching up after a few months. Casual, jokes around, asks about your life. Will share their own news.",
    "openingLine": "Hey, finally! It's been ages. How have you been — like really, what's new?",
    "difficulty": 2,
    "tags": ["friends", "casual", "catchup"],
    "notes": null
  },
  {
    "id": "social-opinion-01",
    "source": "builtin",
    "title": "Movie Discussion",
    "domain": "social",
    "persona": "An opinionated friend named Jordan who just watched a movie you also saw. Will push you to defend your views and share theirs strongly.",
    "openingLine": "OK so — what did you actually think of it? Be honest.",
    "difficulty": 3,
    "tags": ["opinion", "casual", "debate-lite"],
    "notes": null
  }
]
```

- [ ] **Step 4: Implement `ScenarioCatalog`**

`Sources/Core/ScenarioCatalog.swift`:
```swift
import Foundation

public struct ScenarioCatalog: Sendable {
    public let allScenarios: [Scenario]

    public init(allScenarios: [Scenario]) {
        self.allScenarios = allScenarios
    }

    public static func loadBuiltIn() throws -> ScenarioCatalog {
        guard let url = Bundle.module.url(forResource: "built-in-scenarios", withExtension: "json") else {
            throw ScenarioCatalogError.bundledResourceMissing("built-in-scenarios.json")
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([Scenario].self, from: data)
        return ScenarioCatalog(allScenarios: decoded)
    }

    public func scenarios(in domain: ScenarioDomain) -> [Scenario] {
        allScenarios.filter { $0.domain == domain }
    }

    public func scenarios(withTag tag: String) -> [Scenario] {
        allScenarios.filter { $0.tags.contains(tag) }
    }

    public func scenario(id: String) -> Scenario? {
        allScenarios.first { $0.id == id }
    }
}

public enum ScenarioCatalogError: Error, Equatable {
    case bundledResourceMissing(String)
}
```

- [ ] **Step 5: Run tests, confirm pass**

```bash
swift test --filter CoreTests.ScenarioCatalogTests
```

Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Resources/built-in-scenarios.json Sources/Core/ScenarioCatalog.swift Tests/CoreTests/ScenarioCatalogTests.swift
git commit -m "feat(core): add ScenarioCatalog with 6 built-in scenarios"
```

---

## Task 8: `StorageLayout` (filesystem paths)

**Files:**
- Create: `Sources/Persistence/StorageLayout.swift`
- Create: `Tests/PersistenceTests/StorageLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/StorageLayoutTests.swift`:
```swift
import XCTest
@testable import Persistence

final class StorageLayoutTests: XCTestCase {
    func testRootContainsAppNameSegment() {
        let layout = StorageLayout(appName: "EngAssistantTest")
        let root = layout.rootDirectory
        XCTAssertTrue(root.path.contains("EngAssistantTest"), "root: \(root.path)")
        XCTAssertTrue(root.path.contains("Application Support"), "root: \(root.path)")
    }

    func testKnownSubpaths() {
        let layout = StorageLayout(appName: "EngAssistantTest")
        XCTAssertEqual(layout.databaseFile.lastPathComponent, "eng-assistant.sqlite")
        XCTAssertEqual(layout.audioDirectory.lastPathComponent, "audio")
        XCTAssertEqual(layout.transcriptsDirectory.lastPathComponent, "transcripts")
        XCTAssertEqual(layout.modelsDirectory.lastPathComponent, "models")
        XCTAssertEqual(layout.logsDirectory.lastPathComponent, "logs")
    }

    func testEnsureDirectoriesCreatesThem() throws {
        let unique = "EngAssistantTest-\(UUID().uuidString)"
        let layout = StorageLayout(appName: unique)
        try layout.ensureDirectories()
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: layout.rootDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: layout.audioDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: layout.transcriptsDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: layout.modelsDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: layout.logsDirectory.path))
        // cleanup
        try? fm.removeItem(at: layout.rootDirectory)
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.StorageLayoutTests
```

Expected: compile error — `StorageLayout` not found.

- [ ] **Step 3: Implement `StorageLayout`**

`Sources/Persistence/StorageLayout.swift`:
```swift
import Foundation

public struct StorageLayout: Sendable {
    public let appName: String

    public init(appName: String = "EngAssistant") {
        self.appName = appName
    }

    public var rootDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(appName, isDirectory: true)
    }

    public var databaseFile: URL {
        rootDirectory.appendingPathComponent("eng-assistant.sqlite")
    }

    public var audioDirectory: URL {
        rootDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    public var transcriptsDirectory: URL {
        rootDirectory.appendingPathComponent("transcripts", isDirectory: true)
    }

    public var modelsDirectory: URL {
        rootDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public var logsDirectory: URL {
        rootDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [rootDirectory, audioDirectory, transcriptsDirectory, modelsDirectory, logsDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.StorageLayoutTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/StorageLayout.swift Tests/PersistenceTests/StorageLayoutTests.swift
git commit -m "feat(persistence): add StorageLayout with app-support paths"
```

---

## Task 9: `Database` wrapper + first migration

**Files:**
- Create: `Sources/Persistence/Database.swift`
- Create: `Sources/Persistence/Migrations.swift`
- Create: `Tests/PersistenceTests/DatabaseTests.swift`
- Create: `Tests/PersistenceTests/MigrationsTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/PersistenceTests/DatabaseTests.swift`:
```swift
import XCTest
import GRDB
@testable import Persistence

final class DatabaseTests: XCTestCase {
    func testInMemoryDatabaseOpens() throws {
        let db = try Database.inMemory()
        try db.queue.read { _ in /* no-op */ }
    }

    func testRunsMigrationsOnInit() throws {
        let db = try Database.inMemory()
        try db.queue.read { conn in
            let tables = try String.fetchAll(conn, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            XCTAssertTrue(tables.contains("sessions"))
            XCTAssertTrue(tables.contains("turns"))
            XCTAssertTrue(tables.contains("scenarios"))
            XCTAssertTrue(tables.contains("weak_spots"))
            XCTAssertTrue(tables.contains("metrics_daily"))
            XCTAssertTrue(tables.contains("settings"))
        }
    }
}
```

`Tests/PersistenceTests/MigrationsTests.swift`:
```swift
import XCTest
import GRDB
@testable import Persistence

final class MigrationsTests: XCTestCase {
    func testV1CreatesAllExpectedColumnsOnSessions() throws {
        let queue = try DatabaseQueue()
        try Migrations.register().migrate(queue)
        try queue.read { conn in
            let cols = try String.fetchAll(conn, sql: "SELECT name FROM pragma_table_info('sessions')")
            for expected in ["id", "scenario_id", "started_at", "ended_at", "mode", "status", "summary", "persona_snapshot"] {
                XCTAssertTrue(cols.contains(expected), "missing column \(expected) in sessions")
            }
        }
    }

    func testV1CreatesAllExpectedColumnsOnTurns() throws {
        let queue = try DatabaseQueue()
        try Migrations.register().migrate(queue)
        try queue.read { conn in
            let cols = try String.fetchAll(conn, sql: "SELECT name FROM pragma_table_info('turns')")
            for expected in ["id", "session_id", "turn_index", "speaker", "text", "audio_path", "started_at", "duration_ms", "metrics_json", "is_complete"] {
                XCTAssertTrue(cols.contains(expected), "missing column \(expected) in turns")
            }
        }
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.DatabaseTests
swift test --filter PersistenceTests.MigrationsTests
```

Expected: compile errors — `Database`, `Migrations` not found.

- [ ] **Step 3: Implement `Migrations`**

`Sources/Persistence/Migrations.swift`:
```swift
import Foundation
import GRDB

public enum Migrations {
    public static func register() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "scenarios") { t in
                t.column("id", .text).primaryKey()
                t.column("source", .text).notNull()
                t.column("title", .text).notNull()
                t.column("domain", .text).notNull()
                t.column("persona", .text).notNull()
                t.column("opening_line", .text).notNull()
                t.column("difficulty", .integer).notNull()
                t.column("tags_json", .text).notNull()    // JSON array
                t.column("notes", .text)
                t.column("is_user_created", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("scenario_id", .text).notNull()
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("mode", .text).notNull()
                t.column("status", .text).notNull()
                t.column("summary", .text)
                t.column("persona_snapshot", .text).notNull()
            }
            try db.create(index: "idx_sessions_started_at", on: "sessions", columns: ["started_at"])
            try db.create(index: "idx_sessions_status", on: "sessions", columns: ["status"])

            try db.create(table: "turns") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull().references("sessions", onDelete: .cascade)
                t.column("turn_index", .integer).notNull()
                t.column("speaker", .text).notNull()
                t.column("text", .text).notNull()
                t.column("audio_path", .text)
                t.column("started_at", .datetime).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("metrics_json", .text)
                t.column("is_complete", .boolean).notNull().defaults(to: true)
            }
            try db.create(index: "idx_turns_session", on: "turns", columns: ["session_id", "turn_index"])

            try db.create(table: "weak_spots") { t in
                t.column("id", .text).primaryKey()
                t.column("pattern", .text).notNull()
                t.column("category", .text).notNull()
                t.column("first_seen", .datetime).notNull()
                t.column("last_seen", .datetime).notNull()
                t.column("occurrence_count", .integer).notNull().defaults(to: 1)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("example_turn_ids_json", .text).notNull()
            }
            try db.create(index: "idx_weak_spots_status_count",
                          on: "weak_spots",
                          columns: ["status", "occurrence_count"])

            try db.create(table: "metrics_daily") { t in
                t.column("date", .text).primaryKey()
                t.column("total_minutes", .integer).notNull()
                t.column("sessions_count", .integer).notNull()
                t.column("avg_fluency", .double).notNull()
                t.column("avg_vocab_range", .double).notNull()
                t.column("avg_filler_density", .double).notNull()
                t.column("avg_grammar_slips_per_min", .double).notNull()
            }

            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        return migrator
    }
}
```

- [ ] **Step 4: Implement `Database`**

`Sources/Persistence/Database.swift`:
```swift
import Foundation
import GRDB

public final class Database {
    public let queue: DatabaseQueue

    private init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public static func inMemory() throws -> Database {
        let queue = try DatabaseQueue()
        try Migrations.register().migrate(queue)
        return Database(queue: queue)
    }

    public static func onDisk(at url: URL) throws -> Database {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        try Migrations.register().migrate(queue)
        return Database(queue: queue)
    }
}
```

- [ ] **Step 5: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.DatabaseTests
swift test --filter PersistenceTests.MigrationsTests
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Persistence/Database.swift Sources/Persistence/Migrations.swift Tests/PersistenceTests/DatabaseTests.swift Tests/PersistenceTests/MigrationsTests.swift
git commit -m "feat(persistence): add Database wrapper and v1 schema migration"
```

---

## Task 10: `SessionRepository`

**Files:**
- Create: `Sources/Persistence/Repositories/SessionRepository.swift`
- Create: `Tests/PersistenceTests/SessionRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/SessionRepositoryTests.swift`:
```swift
import XCTest
import Core
@testable import Persistence

final class SessionRepositoryTests: XCTestCase {
    private func makeRepo() throws -> (SessionRepository, Database) {
        let db = try Database.inMemory()
        let repo = SessionRepository(database: db)
        return (repo, db)
    }

    private func makeSession(id: UUID = UUID(),
                             status: SessionStatus = .active,
                             ended: Date? = nil) -> Session {
        Session(
            id: id,
            scenarioId: "work-standup-01",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: ended,
            mode: .flow,
            status: status,
            summary: nil,
            personaSnapshot: "A no-nonsense engineering manager."
        )
    }

    func testCreateAndFetchById() throws {
        let (repo, _) = try makeRepo()
        let s = makeSession()
        try repo.create(s)
        let fetched = try repo.find(id: s.id)
        XCTAssertEqual(fetched, s)
    }

    func testFindByIdMissingReturnsNil() throws {
        let (repo, _) = try makeRepo()
        XCTAssertNil(try repo.find(id: UUID()))
    }

    func testFinalizeUpdatesEndedAndStatus() throws {
        let (repo, _) = try makeRepo()
        let s = makeSession()
        try repo.create(s)
        let endTime = Date(timeIntervalSince1970: 1_777_001_000)
        try repo.finalize(id: s.id, endedAt: endTime, summary: "Discussed Q2 goals.")
        let fetched = try repo.find(id: s.id)
        XCTAssertEqual(fetched?.status, .ended)
        XCTAssertEqual(fetched?.endedAt, endTime)
        XCTAssertEqual(fetched?.summary, "Discussed Q2 goals.")
    }

    func testFindOrphanedReturnsActiveOnly() throws {
        let (repo, _) = try makeRepo()
        let active = makeSession(status: .active)
        let ended = makeSession(id: UUID(), status: .ended, ended: Date())
        try repo.create(active)
        try repo.create(ended)
        let orphans = try repo.findOrphaned()
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans.first?.id, active.id)
    }

    func testListByDateRange() throws {
        let (repo, _) = try makeRepo()
        let early = makeSession(id: UUID())
        let late = Session(
            id: UUID(),
            scenarioId: "work-standup-01",
            startedAt: Date(timeIntervalSince1970: 1_777_100_000),
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "test"
        )
        try repo.create(early)
        try repo.create(late)
        let results = try repo.list(
            from: Date(timeIntervalSince1970: 1_777_050_000),
            to: Date(timeIntervalSince1970: 1_777_200_000)
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, late.id)
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.SessionRepositoryTests
```

Expected: compile error — `SessionRepository` not found.

- [ ] **Step 3: Implement `SessionRepository`**

`Sources/Persistence/Repositories/SessionRepository.swift`:
```swift
import Foundation
import Core
import GRDB

public final class SessionRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func create(_ session: Session) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (id, scenario_id, started_at, ended_at, mode, status, summary, persona_snapshot)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                session.id.uuidString,
                session.scenarioId,
                session.startedAt,
                session.endedAt,
                session.mode.rawValue,
                session.status.rawValue,
                session.summary,
                session.personaSnapshot,
            ])
        }
    }

    public func find(id: UUID) throws -> Session? {
        try database.queue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [id.uuidString])
            return row.map(Self.session(from:))
        }
    }

    public func list(from: Date, to: Date) throws -> [Session] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM sessions
                WHERE started_at >= ? AND started_at < ?
                ORDER BY started_at DESC
                """, arguments: [from, to])
                .map(Self.session(from:))
        }
    }

    public func findOrphaned() throws -> [Session] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sessions WHERE status = 'active'")
                .map(Self.session(from:))
        }
    }

    public func finalize(id: UUID, endedAt: Date, summary: String?) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                UPDATE sessions SET ended_at = ?, status = 'ended', summary = ? WHERE id = ?
                """, arguments: [endedAt, summary, id.uuidString])
        }
    }

    public func markAbandoned(id: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE sessions SET status = 'abandoned' WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    private static func session(from row: Row) -> Session {
        Session(
            id: UUID(uuidString: row["id"])!,
            scenarioId: row["scenario_id"],
            startedAt: row["started_at"],
            endedAt: row["ended_at"],
            mode: SessionMode(rawValue: row["mode"])!,
            status: SessionStatus(rawValue: row["status"])!,
            summary: row["summary"],
            personaSnapshot: row["persona_snapshot"]
        )
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.SessionRepositoryTests
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/Repositories/SessionRepository.swift Tests/PersistenceTests/SessionRepositoryTests.swift
git commit -m "feat(persistence): add SessionRepository CRUD + orphan detection"
```

---

## Task 11: `TurnRepository`

**Files:**
- Create: `Sources/Persistence/Repositories/TurnRepository.swift`
- Create: `Tests/PersistenceTests/TurnRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/TurnRepositoryTests.swift`:
```swift
import XCTest
import Core
@testable import Persistence

final class TurnRepositoryTests: XCTestCase {
    private func setup() throws -> (TurnRepository, SessionRepository, UUID) {
        let db = try Database.inMemory()
        let sessionRepo = SessionRepository(database: db)
        let turnRepo = TurnRepository(database: db)
        let sessionId = UUID()
        try sessionRepo.create(Session(
            id: sessionId,
            scenarioId: "work-standup-01",
            startedAt: Date(timeIntervalSince1970: 1_777_000_000),
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "test"
        ))
        return (turnRepo, sessionRepo, sessionId)
    }

    private func makeTurn(sessionId: UUID, index: Int, speaker: Speaker, complete: Bool = true) -> Turn {
        Turn(
            id: UUID(),
            sessionId: sessionId,
            turnIndex: index,
            speaker: speaker,
            text: "Sample text \(index)",
            audioPath: speaker == .user ? "audio/x/user-turn-\(index).wav" : nil,
            startedAt: Date(timeIntervalSince1970: 1_777_000_000 + Double(index * 10)),
            durationMs: 3000,
            metricsJson: nil,
            isComplete: complete
        )
    }

    func testAppendAndList() throws {
        let (turnRepo, _, sessionId) = try setup()
        try turnRepo.append(makeTurn(sessionId: sessionId, index: 0, speaker: .user))
        try turnRepo.append(makeTurn(sessionId: sessionId, index: 1, speaker: .ai))
        let turns = try turnRepo.list(forSession: sessionId)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.map(\.turnIndex), [0, 1])
    }

    func testMarkIncomplete() throws {
        let (turnRepo, _, sessionId) = try setup()
        let t = makeTurn(sessionId: sessionId, index: 0, speaker: .ai, complete: true)
        try turnRepo.append(t)
        try turnRepo.markIncomplete(id: t.id)
        let turns = try turnRepo.list(forSession: sessionId)
        XCTAssertEqual(turns.first?.isComplete, false)
    }

    func testFindIncompleteTurnsForSession() throws {
        let (turnRepo, _, sessionId) = try setup()
        try turnRepo.append(makeTurn(sessionId: sessionId, index: 0, speaker: .user, complete: true))
        try turnRepo.append(makeTurn(sessionId: sessionId, index: 1, speaker: .ai, complete: false))
        let incomplete = try turnRepo.listIncomplete(forSession: sessionId)
        XCTAssertEqual(incomplete.count, 1)
        XCTAssertEqual(incomplete.first?.turnIndex, 1)
    }

    func testUpdateMetricsJson() throws {
        let (turnRepo, _, sessionId) = try setup()
        let t = makeTurn(sessionId: sessionId, index: 0, speaker: .user)
        try turnRepo.append(t)
        try turnRepo.updateMetricsJson(turnId: t.id, json: "{\"wordsPerMinute\":120}")
        let turns = try turnRepo.list(forSession: sessionId)
        XCTAssertEqual(turns.first?.metricsJson, "{\"wordsPerMinute\":120}")
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.TurnRepositoryTests
```

Expected: compile error — `TurnRepository` not found.

- [ ] **Step 3: Implement `TurnRepository`**

`Sources/Persistence/Repositories/TurnRepository.swift`:
```swift
import Foundation
import Core
import GRDB

public final class TurnRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func append(_ turn: Turn) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO turns (id, session_id, turn_index, speaker, text, audio_path,
                                   started_at, duration_ms, metrics_json, is_complete)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                turn.id.uuidString,
                turn.sessionId.uuidString,
                turn.turnIndex,
                turn.speaker.rawValue,
                turn.text,
                turn.audioPath,
                turn.startedAt,
                turn.durationMs,
                turn.metricsJson,
                turn.isComplete,
            ])
        }
    }

    public func list(forSession sessionId: UUID) throws -> [Turn] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM turns WHERE session_id = ? ORDER BY turn_index ASC
                """, arguments: [sessionId.uuidString])
                .map(Self.turn(from:))
        }
    }

    public func listIncomplete(forSession sessionId: UUID) throws -> [Turn] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM turns WHERE session_id = ? AND is_complete = 0 ORDER BY turn_index ASC
                """, arguments: [sessionId.uuidString])
                .map(Self.turn(from:))
        }
    }

    public func markIncomplete(id: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE turns SET is_complete = 0 WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    public func updateMetricsJson(turnId: UUID, json: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE turns SET metrics_json = ? WHERE id = ?",
                           arguments: [json, turnId.uuidString])
        }
    }

    private static func turn(from row: Row) -> Turn {
        Turn(
            id: UUID(uuidString: row["id"])!,
            sessionId: UUID(uuidString: row["session_id"])!,
            turnIndex: row["turn_index"],
            speaker: Speaker(rawValue: row["speaker"])!,
            text: row["text"],
            audioPath: row["audio_path"],
            startedAt: row["started_at"],
            durationMs: row["duration_ms"],
            metricsJson: row["metrics_json"],
            isComplete: row["is_complete"]
        )
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.TurnRepositoryTests
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/Repositories/TurnRepository.swift Tests/PersistenceTests/TurnRepositoryTests.swift
git commit -m "feat(persistence): add TurnRepository (append, list, mark-incomplete, update-metrics)"
```

---

## Task 12: `ScenarioRepository` (custom scenarios in DB)

**Files:**
- Create: `Sources/Persistence/Repositories/ScenarioRepository.swift`
- Create: `Tests/PersistenceTests/ScenarioRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/ScenarioRepositoryTests.swift`:
```swift
import XCTest
import Core
@testable import Persistence

final class ScenarioRepositoryTests: XCTestCase {
    private func makeRepo() throws -> ScenarioRepository {
        ScenarioRepository(database: try Database.inMemory())
    }

    private func makeCustom(id: String = "custom-1") -> Scenario {
        Scenario(
            id: id,
            source: .custom,
            title: "Manager 1:1 Tomorrow",
            domain: .work,
            persona: "My new manager Priya, friendly but skeptical.",
            openingLine: "So, how's it been going?",
            difficulty: 3,
            tags: ["1on1", "manager"],
            notes: "Q2 goals discussion."
        )
    }

    func testCreateAndFind() throws {
        let repo = try makeRepo()
        let s = makeCustom()
        try repo.create(s)
        let found = try repo.find(id: s.id)
        XCTAssertEqual(found, s)
    }

    func testListAllCustomOnly() throws {
        let repo = try makeRepo()
        try repo.create(makeCustom(id: "custom-a"))
        try repo.create(makeCustom(id: "custom-b"))
        let all = try repo.listCustom()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.source == .custom })
    }

    func testDelete() throws {
        let repo = try makeRepo()
        let s = makeCustom()
        try repo.create(s)
        try repo.delete(id: s.id)
        XCTAssertNil(try repo.find(id: s.id))
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.ScenarioRepositoryTests
```

Expected: compile error — `ScenarioRepository` not found.

- [ ] **Step 3: Implement `ScenarioRepository`**

`Sources/Persistence/Repositories/ScenarioRepository.swift`:
```swift
import Foundation
import Core
import GRDB

public final class ScenarioRepository {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) {
        self.database = database
    }

    public func create(_ scenario: Scenario) throws {
        let tagsJson = String(data: try encoder.encode(scenario.tags), encoding: .utf8)!
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO scenarios (id, source, title, domain, persona, opening_line,
                                       difficulty, tags_json, notes, is_user_created)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                scenario.id,
                scenario.source.rawValue,
                scenario.title,
                scenario.domain.rawValue,
                scenario.persona,
                scenario.openingLine,
                scenario.difficulty,
                tagsJson,
                scenario.notes,
                scenario.source == .custom,
            ])
        }
    }

    public func find(id: String) throws -> Scenario? {
        try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM scenarios WHERE id = ?", arguments: [id])
                .map { try Self.scenario(from: $0, decoder: self.decoder) }
        }
    }

    public func listCustom() throws -> [Scenario] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scenarios WHERE source = 'custom' ORDER BY title")
                .map { try Self.scenario(from: $0, decoder: self.decoder) }
        }
    }

    public func delete(id: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM scenarios WHERE id = ?", arguments: [id])
        }
    }

    private static func scenario(from row: Row, decoder: JSONDecoder) throws -> Scenario {
        let tagsJson: String = row["tags_json"]
        let tags = (try? decoder.decode([String].self, from: Data(tagsJson.utf8))) ?? []
        return Scenario(
            id: row["id"],
            source: ScenarioSource(rawValue: row["source"])!,
            title: row["title"],
            domain: ScenarioDomain(rawValue: row["domain"])!,
            persona: row["persona"],
            openingLine: row["opening_line"],
            difficulty: row["difficulty"],
            tags: tags,
            notes: row["notes"]
        )
    }
}
```

Note: `find(id:)` and `listCustom()` use a closure that throws, hence the `try` prefix on `Row.fetchOne(...)` chain. If the compiler complains about the `.map { try ... }` form, change to a `for`-loop in those methods. The mapping closure must be marked `throws`.

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.ScenarioRepositoryTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/Repositories/ScenarioRepository.swift Tests/PersistenceTests/ScenarioRepositoryTests.swift
git commit -m "feat(persistence): add ScenarioRepository for custom scenarios"
```

---

## Task 13: `WeakSpotRepository` with dedup query

**Files:**
- Create: `Sources/Persistence/Repositories/WeakSpotRepository.swift`
- Create: `Tests/PersistenceTests/WeakSpotRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/WeakSpotRepositoryTests.swift`:
```swift
import XCTest
import Core
@testable import Persistence

final class WeakSpotRepositoryTests: XCTestCase {
    private func makeRepo() throws -> WeakSpotRepository {
        WeakSpotRepository(database: try Database.inMemory())
    }

    private let now = Date(timeIntervalSince1970: 1_777_000_000)

    func testCreateAndFindByPattern() throws {
        let repo = try makeRepo()
        let ws = WeakSpot(
            id: UUID(),
            pattern: "uses 'more better' instead of 'better'",
            category: .grammar,
            firstSeen: now,
            lastSeen: now,
            occurrenceCount: 1,
            status: .active,
            exampleTurnIds: [UUID()]
        )
        try repo.create(ws)
        let found = try repo.findByPattern(ws.pattern)
        XCTAssertEqual(found?.id, ws.id)
    }

    func testIncrementOccurrence() throws {
        let repo = try makeRepo()
        let ws = WeakSpot(
            id: UUID(),
            pattern: "stutters on conditionals",
            category: .fluency,
            firstSeen: now,
            lastSeen: now,
            occurrenceCount: 1,
            status: .active,
            exampleTurnIds: []
        )
        try repo.create(ws)
        let later = now.addingTimeInterval(60)
        let newTurnId = UUID()
        try repo.incrementOccurrence(id: ws.id, lastSeen: later, addExampleTurnId: newTurnId)
        let updated = try repo.findByPattern(ws.pattern)
        XCTAssertEqual(updated?.occurrenceCount, 2)
        XCTAssertEqual(updated?.lastSeen, later)
        XCTAssertEqual(updated?.exampleTurnIds, [newTurnId])
    }

    func testListActiveByFrequency() throws {
        let repo = try makeRepo()
        let a = WeakSpot(id: UUID(), pattern: "p1", category: .grammar, firstSeen: now, lastSeen: now,
                         occurrenceCount: 1, status: .active, exampleTurnIds: [])
        let b = WeakSpot(id: UUID(), pattern: "p2", category: .grammar, firstSeen: now, lastSeen: now,
                         occurrenceCount: 5, status: .active, exampleTurnIds: [])
        let c = WeakSpot(id: UUID(), pattern: "p3", category: .grammar, firstSeen: now, lastSeen: now,
                         occurrenceCount: 3, status: .resolved, exampleTurnIds: [])
        try repo.create(a); try repo.create(b); try repo.create(c)
        let active = try repo.listActiveByFrequency(limit: 10)
        XCTAssertEqual(active.map(\.pattern), ["p2", "p1"])
    }

    func testMarkResolved() throws {
        let repo = try makeRepo()
        let ws = WeakSpot(id: UUID(), pattern: "p1", category: .filler,
                          firstSeen: now, lastSeen: now,
                          occurrenceCount: 1, status: .active, exampleTurnIds: [])
        try repo.create(ws)
        try repo.markResolved(id: ws.id)
        let found = try repo.findByPattern("p1")
        XCTAssertEqual(found?.status, .resolved)
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.WeakSpotRepositoryTests
```

Expected: compile error — `WeakSpotRepository` not found.

- [ ] **Step 3: Implement `WeakSpotRepository`**

`Sources/Persistence/Repositories/WeakSpotRepository.swift`:
```swift
import Foundation
import Core
import GRDB

public final class WeakSpotRepository {
    private let database: Database
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: Database) {
        self.database = database
    }

    public func create(_ ws: WeakSpot) throws {
        let json = String(data: try encoder.encode(ws.exampleTurnIds.map { $0.uuidString }),
                          encoding: .utf8)!
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO weak_spots (id, pattern, category, first_seen, last_seen,
                                        occurrence_count, status, example_turn_ids_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                ws.id.uuidString,
                ws.pattern,
                ws.category.rawValue,
                ws.firstSeen,
                ws.lastSeen,
                ws.occurrenceCount,
                ws.status.rawValue,
                json,
            ])
        }
    }

    public func findByPattern(_ pattern: String) throws -> WeakSpot? {
        try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM weak_spots WHERE pattern = ?",
                             arguments: [pattern])
                .map { try Self.weakSpot(from: $0, decoder: self.decoder) }
        }
    }

    public func incrementOccurrence(id: UUID, lastSeen: Date, addExampleTurnId: UUID?) throws {
        try database.queue.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM weak_spots WHERE id = ?",
                                             arguments: [id.uuidString]) else {
                throw WeakSpotRepositoryError.notFound(id)
            }
            let existing = try Self.weakSpot(from: row, decoder: self.decoder)
            var ids = existing.exampleTurnIds
            if let newId = addExampleTurnId, !ids.contains(newId) {
                ids.append(newId)
            }
            let json = String(data: try encoder.encode(ids.map { $0.uuidString }), encoding: .utf8)!
            try db.execute(sql: """
                UPDATE weak_spots SET occurrence_count = occurrence_count + 1,
                                      last_seen = ?,
                                      example_turn_ids_json = ?
                WHERE id = ?
                """, arguments: [lastSeen, json, id.uuidString])
        }
    }

    public func listActiveByFrequency(limit: Int) throws -> [WeakSpot] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM weak_spots WHERE status = 'active'
                ORDER BY occurrence_count DESC, last_seen DESC
                LIMIT ?
                """, arguments: [limit])
                .map { try Self.weakSpot(from: $0, decoder: self.decoder) }
        }
    }

    public func markResolved(id: UUID) throws {
        try database.queue.write { db in
            try db.execute(sql: "UPDATE weak_spots SET status = 'resolved' WHERE id = ?",
                           arguments: [id.uuidString])
        }
    }

    private static func weakSpot(from row: Row, decoder: JSONDecoder) throws -> WeakSpot {
        let json: String = row["example_turn_ids_json"]
        let stringIds = (try? decoder.decode([String].self, from: Data(json.utf8))) ?? []
        let ids = stringIds.compactMap { UUID(uuidString: $0) }
        return WeakSpot(
            id: UUID(uuidString: row["id"])!,
            pattern: row["pattern"],
            category: WeakSpotCategory(rawValue: row["category"])!,
            firstSeen: row["first_seen"],
            lastSeen: row["last_seen"],
            occurrenceCount: row["occurrence_count"],
            status: WeakSpotStatus(rawValue: row["status"])!,
            exampleTurnIds: ids
        )
    }
}

public enum WeakSpotRepositoryError: Error, Equatable {
    case notFound(UUID)
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.WeakSpotRepositoryTests
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/Repositories/WeakSpotRepository.swift Tests/PersistenceTests/WeakSpotRepositoryTests.swift
git commit -m "feat(persistence): add WeakSpotRepository with dedup + frequency listing"
```

---

## Task 14: `MetricsRepository`

**Files:**
- Create: `Sources/Persistence/Repositories/MetricsRepository.swift`
- Create: `Tests/PersistenceTests/MetricsRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/MetricsRepositoryTests.swift`:
```swift
import XCTest
import Core
@testable import Persistence

final class MetricsRepositoryTests: XCTestCase {
    private func makeRepo() throws -> MetricsRepository {
        MetricsRepository(database: try Database.inMemory())
    }

    private func sample(date: String, sessions: Int = 1, fluency: Double = 130) -> DailyMetrics {
        DailyMetrics(
            date: date,
            totalMinutes: 20,
            sessionsCount: sessions,
            avgFluency: fluency,
            avgVocabRange: 0.7,
            avgFillerDensity: 0.05,
            avgGrammarSlipsPerMin: 0.5
        )
    }

    func testUpsertCreatesAndReplaces() throws {
        let repo = try makeRepo()
        try repo.upsert(sample(date: "2026-05-04", fluency: 130))
        try repo.upsert(sample(date: "2026-05-04", fluency: 140))
        let fetched = try repo.find(date: "2026-05-04")
        XCTAssertEqual(fetched?.avgFluency, 140)
    }

    func testListRecentOrderedDesc() throws {
        let repo = try makeRepo()
        try repo.upsert(sample(date: "2026-05-01"))
        try repo.upsert(sample(date: "2026-05-04"))
        try repo.upsert(sample(date: "2026-05-02"))
        let recent = try repo.listRecent(days: 30)
        XCTAssertEqual(recent.map(\.date), ["2026-05-04", "2026-05-02", "2026-05-01"])
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.MetricsRepositoryTests
```

Expected: compile error.

- [ ] **Step 3: Implement `MetricsRepository`**

`Sources/Persistence/Repositories/MetricsRepository.swift`:
```swift
import Foundation
import Core
import GRDB

public final class MetricsRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func upsert(_ m: DailyMetrics) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO metrics_daily (date, total_minutes, sessions_count, avg_fluency,
                                           avg_vocab_range, avg_filler_density, avg_grammar_slips_per_min)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    total_minutes = excluded.total_minutes,
                    sessions_count = excluded.sessions_count,
                    avg_fluency = excluded.avg_fluency,
                    avg_vocab_range = excluded.avg_vocab_range,
                    avg_filler_density = excluded.avg_filler_density,
                    avg_grammar_slips_per_min = excluded.avg_grammar_slips_per_min
                """, arguments: [
                m.date, m.totalMinutes, m.sessionsCount, m.avgFluency,
                m.avgVocabRange, m.avgFillerDensity, m.avgGrammarSlipsPerMin,
            ])
        }
    }

    public func find(date: String) throws -> DailyMetrics? {
        try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM metrics_daily WHERE date = ?", arguments: [date])
                .map(Self.daily(from:))
        }
    }

    public func listRecent(days: Int) throws -> [DailyMetrics] {
        try database.queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM metrics_daily ORDER BY date DESC LIMIT ?
                """, arguments: [days])
                .map(Self.daily(from:))
        }
    }

    private static func daily(from row: Row) -> DailyMetrics {
        DailyMetrics(
            date: row["date"],
            totalMinutes: row["total_minutes"],
            sessionsCount: row["sessions_count"],
            avgFluency: row["avg_fluency"],
            avgVocabRange: row["avg_vocab_range"],
            avgFillerDensity: row["avg_filler_density"],
            avgGrammarSlipsPerMin: row["avg_grammar_slips_per_min"]
        )
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.MetricsRepositoryTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/Repositories/MetricsRepository.swift Tests/PersistenceTests/MetricsRepositoryTests.swift
git commit -m "feat(persistence): add MetricsRepository (daily upsert + listing)"
```

---

## Task 15: `SettingsRepository`

**Files:**
- Create: `Sources/Persistence/Repositories/SettingsRepository.swift`
- Create: `Tests/PersistenceTests/SettingsRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PersistenceTests/SettingsRepositoryTests.swift`:
```swift
import XCTest
import Core
@testable import Persistence

final class SettingsRepositoryTests: XCTestCase {
    private func makeRepo() throws -> SettingsRepository {
        SettingsRepository(database: try Database.inMemory())
    }

    func testGetMissingReturnsNil() throws {
        let repo = try makeRepo()
        XCTAssertNil(try repo.get(.defaultMode))
    }

    func testSetThenGet() throws {
        let repo = try makeRepo()
        try repo.set(.defaultMode, value: "flow")
        XCTAssertEqual(try repo.get(.defaultMode), "flow")
    }

    func testOverwrite() throws {
        let repo = try makeRepo()
        try repo.set(.audioRetentionDays, value: "30")
        try repo.set(.audioRetentionDays, value: "7")
        XCTAssertEqual(try repo.get(.audioRetentionDays), "7")
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

```bash
swift test --filter PersistenceTests.SettingsRepositoryTests
```

Expected: compile error.

- [ ] **Step 3: Implement `SettingsRepository`**

`Sources/Persistence/Repositories/SettingsRepository.swift`:
```swift
import Foundation
import Core
import GRDB

public final class SettingsRepository {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func get(_ key: AppSettingKey) throws -> String? {
        try database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?",
                             arguments: [key.rawValue])
                .map { $0["value"] }
        }
    }

    public func set(_ key: AppSettingKey, value: String) throws {
        try database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [key.rawValue, value])
        }
    }
}
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
swift test --filter PersistenceTests.SettingsRepositoryTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/Repositories/SettingsRepository.swift Tests/PersistenceTests/SettingsRepositoryTests.swift
git commit -m "feat(persistence): add SettingsRepository (key/value store)"
```

---

## Task 16: SmokeCLI end-to-end verifier

**Files:**
- Modify: `Sources/SmokeCLI/main.swift`

- [ ] **Step 1: Replace `main.swift` with a real smoke test**

`Sources/SmokeCLI/main.swift`:
```swift
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
```

- [ ] **Step 2: Build and run the smoke CLI**

```bash
swift build
swift run smoke-cli
```

Expected output (timestamps will differ):
```
→ Opening DB at /tmp/eng-assistant-smoke.sqlite
→ Loading built-in scenarios
  loaded 6 scenarios
→ Using scenario: Daily Engineering Standup
→ Created session ...
→ Appended 4 turns
→ Recorded 1 weak spot
→ Finalized session

=== Result ===
Session status: ended
Summary: Standup practice run.
Turns: 4
  [0] ai: Good morning. What did you finish yesterday, and what are you picking up today?
  [1] user: Yesterday I finished the auth refactor. ...
  [2] ai: Any blockers I should know about?
  [3] user: No blockers, but I'd like a review on the auth PR before EOD.
Active weak spots: 1
  - uses passive 'I'd like a review' instead of asking directly (vocab, seen 1x)

✓ smoke OK
```

- [ ] **Step 3: Run all tests once more for sanity**

```bash
swift test
```

Expected: all tests pass (every suite from Tasks 1-15).

- [ ] **Step 4: Commit**

```bash
git add Sources/SmokeCLI/main.swift
git commit -m "feat(smoke): wire CLI smoke test that exercises Core + Persistence"
```

---

## Plan 1 Self-Review

Verifying the plan covers everything in scope:

| Spec requirement | Covered by |
|---|---|
| SPM workspace with `Core`, `Persistence` modules | Task 1 |
| `Core` has no AppKit/SwiftUI dependency | Task 1 (Package.swift defines Core with no UI deps) |
| All domain types from Section 5 schema | Tasks 2-6 (Scenario, Session, Turn, WeakSpot, Metrics, Settings keys) |
| Built-in scenarios with all three domains | Task 7 (6 scenarios, 2 per domain) |
| `ScenarioCatalog` with filtering | Task 7 |
| Storage layout under `~/Library/Application Support/EngAssistant/` | Task 8 |
| GRDB-backed SQLite with all six tables | Task 9 |
| Versioned migrations | Task 9 |
| `sessions` CRUD + orphan detection | Task 10 |
| `turns` CRUD + mark-incomplete | Task 11 |
| Custom scenarios in DB | Task 12 |
| `weak_spots` dedup + frequency listing | Task 13 |
| `metrics_daily` rollup storage | Task 14 |
| `settings` key/value | Task 15 |
| End-to-end smoke verification | Task 16 |

**Out-of-scope confirmation (handled in later plans, NOT this one):**
- SessionEngine / PersonaBuilder / MetricsAnalyzer / WeakSpotExtractor — Plan 2 & 3
- Adapter protocols + concrete impls — Plan 2 & 4
- Audio capture / playback — Plan 5
- UI screens — Plan 6
- Onboarding wizard — Plan 6
- Audio retention sweeper (depends on real audio files existing) — Plan 5/6
- Transcript markdown mirror (depends on session running) — Plan 2 or 3

This is a focused, self-contained plan that ends with a working data layer and CLI verifier.

---

## Definition of Done (Plan 1)

- `swift build` succeeds with no warnings.
- `swift test` runs all suites (~30+ tests) and they all pass.
- `swift run smoke-cli` produces the expected output and exits 0.
- One git commit per task (16 commits + the initial spec commits already in place).
- No file-internal placeholders, TODOs, or unfinished functions.
