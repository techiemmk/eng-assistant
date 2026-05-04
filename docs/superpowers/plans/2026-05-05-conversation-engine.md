# Conversation Engine (Fakes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the conversation orchestration layer end-to-end using *fake* STT/LLM/TTS providers. By the end, a `SessionEngine` actor can drive a complete simulated session through the persistence layer from Plan 1, producing real `sessions` and `turns` rows. No real audio or model calls — those land in Plans 4 and 5.

**Architecture:** All adapter protocols and the `SessionEngine` live in `Core` (no dependency on Persistence or external SDKs). Persistence repository classes get small extensions in `Persistence/` that conform them to thin "persister" protocols defined in `Core`, so `SessionEngine` only sees protocols. A new SPM target `Fakes` provides scripted in-memory implementations of every adapter, usable from both tests and the `SmokeCLI` demo.

**Tech Stack:** Swift 5.9+, Swift Package Manager, Swift Structured Concurrency (`actor`, `AsyncStream`), Swift Testing.

**Test runner:** This environment uses Apple Command Line Tools (no Xcode), so use `bin/test.sh` everywhere this plan says `swift test`. Test framework is **Swift Testing** (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`).

**Git committer:** All implementer subagents are dispatched with `git -c user.email=techiemmk@gmail.com -c user.name="Manoj"` (no global git config in this environment).

---

## File Structure

```
Sources/
├── Core/
│   ├── Models/                          # already exists from Plan 1
│   ├── ScenarioCatalog.swift            # already exists
│   ├── Adapters/                        # NEW — all in Core, protocols only
│   │   ├── ChatMessage.swift
│   │   ├── LLMProvider.swift
│   │   ├── STTProvider.swift
│   │   ├── TTSProvider.swift
│   │   ├── AudioCapture.swift
│   │   └── AudioPlayback.swift
│   ├── Persisters/                      # NEW — protocols Persistence will conform to
│   │   ├── SessionPersisting.swift
│   │   ├── TurnPersisting.swift
│   │   └── WeakSpotPersisting.swift
│   └── Engine/                          # NEW — domain logic
│       ├── CoachMarkerParser.swift
│       ├── PersonaBuilder.swift
│       ├── ChatHistory.swift
│       └── SessionEngine.swift
├── Persistence/                         # already exists
│   └── Conformances/                    # NEW — tiny extension files
│       ├── SessionRepository+SessionPersisting.swift
│       ├── TurnRepository+TurnPersisting.swift
│       └── WeakSpotRepository+WeakSpotPersisting.swift
├── Fakes/                               # NEW SPM target — depends on Core
│   ├── FakeLLMProvider.swift
│   ├── FakeSTTProvider.swift
│   ├── FakeTTSProvider.swift
│   ├── FakeAudioCapture.swift
│   └── FakeAudioPlayback.swift
└── SmokeCLI/main.swift                  # extended to demo a fake session via SessionEngine

Tests/
├── CoreTests/
│   ├── CoachMarkerParserTests.swift     # NEW
│   ├── PersonaBuilderTests.swift        # NEW
│   ├── ChatHistoryTests.swift           # NEW
│   └── SessionEngineTests.swift         # NEW (uses Fakes target)
└── PersistenceTests/                    # unchanged
```

**Per-file responsibility:**

| File | Responsibility |
|---|---|
| `ChatMessage.swift` | `ChatRole` enum + `ChatMessage` value type (`role`, `content`). |
| `LLMProvider.swift` | `LLMProvider` protocol — `respond(messages:options:) async throws -> AsyncStream<String>`; `LLMOptions` (temperature, maxTokens, model name). |
| `STTProvider.swift` | `STTProvider` protocol + `Transcript` (text, confidence). |
| `TTSProvider.swift` | `TTSProvider` protocol + `Voice` (id) + `SynthesizedAudio` (data, sampleRate). |
| `AudioCapture.swift` | `AudioCapture` protocol — `startRecording()`, `stopRecording() -> Data`. |
| `AudioPlayback.swift` | `AudioPlayback` protocol — `play(_ audio: SynthesizedAudio) async throws`. |
| `SessionPersisting.swift`, `TurnPersisting.swift`, `WeakSpotPersisting.swift` | Subset protocols of the existing repositories' surface that `SessionEngine` actually needs. |
| `CoachMarkerParser.swift` | Parses `[[coach: …]]` markers out of LLM output; returns clean spoken text + structured `Correction` array. |
| `PersonaBuilder.swift` | Composes the LLM system prompt from `Scenario` + `SessionMode` + `[WeakSpot]`. |
| `ChatHistory.swift` | In-memory rolling history; truncates by character budget (proxy for token count); always preserves the system message. |
| `SessionEngine.swift` | Actor. `start(scenario:mode:weakSpots:)`, `runUserTurn(audio:)` async, `end(summary:)`. Orchestrates STT → LLM → marker-parse → TTS, persists every turn. |
| `Fakes/*` | Scripted, configurable in-memory implementations. |
| `Conformances/*` | One-line `extension SessionRepository: SessionPersisting {}` etc. |

---

## Task Decomposition Notes

- TDD throughout. Every task: failing test → run (red) → minimal impl → run (green) → commit.
- Conventional commit prefixes: `feat(core):`, `feat(fakes):`, `feat(persistence):`, `feat(smoke):`, `test(...)`.
- Tests use the `Fakes` target rather than ad-hoc inline mocks.
- Each commit must leave `bin/test.sh` all green.

---

## Task 1 — Define adapter value types & `LLMProvider`

Sets the foundational shapes used by every other component.

**Files:**
- Create: `Sources/Core/Adapters/ChatMessage.swift`
- Create: `Sources/Core/Adapters/LLMProvider.swift`

- [ ] **Step 1 — Write the failing test (no separate test file; tests for protocols come implicitly via Fakes in later tasks). Skip the test step for this task only — it's pure type-shape definition with no behavior.**

Note: For type-only definitions there's nothing meaningful to assert. The "test" is that downstream code (in later tasks) compiles. Move directly to Step 2.

- [ ] **Step 2 — Implement `ChatMessage`**

`Sources/Core/Adapters/ChatMessage.swift`:
```swift
import Foundation

public enum ChatRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public let role: ChatRole
    public let content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}
```

- [ ] **Step 3 — Implement `LLMProvider` & options**

`Sources/Core/Adapters/LLMProvider.swift`:
```swift
import Foundation

public struct LLMOptions: Equatable, Sendable {
    public var modelName: String
    public var temperature: Double
    public var maxTokens: Int

    public init(modelName: String, temperature: Double = 0.7, maxTokens: Int = 512) {
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public protocol LLMProvider: Sendable {
    /// Streams reply tokens. The stream yields chunks of text; the caller
    /// concatenates them. The stream finishes (without throwing) when the
    /// reply is complete.
    func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error>
}
```

- [ ] **Step 4 — Build to verify**

```bash
swift build
```

Expected: succeeds with no warnings.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Adapters/ChatMessage.swift Sources/Core/Adapters/LLMProvider.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add ChatMessage, ChatRole, LLMProvider, LLMOptions"
```

---

## Task 2 — STT / TTS / Audio adapter protocols

**Files:**
- Create: `Sources/Core/Adapters/STTProvider.swift`
- Create: `Sources/Core/Adapters/TTSProvider.swift`
- Create: `Sources/Core/Adapters/AudioCapture.swift`
- Create: `Sources/Core/Adapters/AudioPlayback.swift`

- [ ] **Step 1 — Implement STTProvider**

`Sources/Core/Adapters/STTProvider.swift`:
```swift
import Foundation

public struct Transcript: Equatable, Sendable {
    public var text: String
    public var confidence: Double  // 0..1

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public protocol STTProvider: Sendable {
    func transcribe(audio: Data) async throws -> Transcript
}
```

- [ ] **Step 2 — Implement TTSProvider**

`Sources/Core/Adapters/TTSProvider.swift`:
```swift
import Foundation

public struct Voice: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct SynthesizedAudio: Equatable, Sendable {
    public let data: Data
    public let sampleRate: Int

    public init(data: Data, sampleRate: Int) {
        self.data = data
        self.sampleRate = sampleRate
    }
}

public protocol TTSProvider: Sendable {
    func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio
}
```

- [ ] **Step 3 — Implement AudioCapture**

`Sources/Core/Adapters/AudioCapture.swift`:
```swift
import Foundation

public protocol AudioCapture: Sendable {
    /// Begin recording from the microphone. Returns immediately.
    func startRecording() async throws

    /// Stop recording and return the raw audio bytes. The format is
    /// implementation-defined; the matching `STTProvider` must accept it.
    func stopRecording() async throws -> Data
}
```

- [ ] **Step 4 — Implement AudioPlayback**

`Sources/Core/Adapters/AudioPlayback.swift`:
```swift
import Foundation

public protocol AudioPlayback: Sendable {
    func play(_ audio: SynthesizedAudio) async throws
}
```

- [ ] **Step 5 — Build to verify**

```bash
swift build
```

Expected: succeeds with no warnings.

- [ ] **Step 6 — Commit**

```bash
git add Sources/Core/Adapters/STTProvider.swift \
        Sources/Core/Adapters/TTSProvider.swift \
        Sources/Core/Adapters/AudioCapture.swift \
        Sources/Core/Adapters/AudioPlayback.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add STTProvider, TTSProvider, AudioCapture, AudioPlayback protocols"
```

---

## Task 3 — Persister protocols + conformances

`SessionEngine` will need to call into the persistence layer, but `Core` cannot depend on `Persistence` (that would invert the layering). Solution: declare narrow protocols in `Core`, conform the existing `Persistence` repository classes to them via tiny extension files.

**Files:**
- Create: `Sources/Core/Persisters/SessionPersisting.swift`
- Create: `Sources/Core/Persisters/TurnPersisting.swift`
- Create: `Sources/Core/Persisters/WeakSpotPersisting.swift`
- Create: `Sources/Persistence/Conformances/SessionRepository+SessionPersisting.swift`
- Create: `Sources/Persistence/Conformances/TurnRepository+TurnPersisting.swift`
- Create: `Sources/Persistence/Conformances/WeakSpotRepository+WeakSpotPersisting.swift`
- Create: `Tests/PersistenceTests/PersisterConformanceTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/PersistenceTests/PersisterConformanceTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Persistence

@Suite struct PersisterConformanceTests {
    @Test func sessionRepositoryConformsToSessionPersisting() throws {
        let db = try Database.inMemory()
        let repo: any SessionPersisting = SessionRepository(database: db)
        let id = UUID()
        try repo.create(Session(
            id: id,
            scenarioId: "s",
            startedAt: Date(),
            endedAt: nil,
            mode: .flow,
            status: .active,
            summary: nil,
            personaSnapshot: "p"
        ))
        #expect(try repo.find(id: id)?.id == id)
    }

    @Test func turnRepositoryConformsToTurnPersisting() throws {
        let db = try Database.inMemory()
        let sessionRepo = SessionRepository(database: db)
        let sessionId = UUID()
        try sessionRepo.create(Session(
            id: sessionId, scenarioId: "s", startedAt: Date(), endedAt: nil,
            mode: .flow, status: .active, summary: nil, personaSnapshot: "p"
        ))
        let repo: any TurnPersisting = TurnRepository(database: db)
        try repo.append(Turn(
            id: UUID(), sessionId: sessionId, turnIndex: 0, speaker: .user,
            text: "hi", audioPath: nil, startedAt: Date(),
            durationMs: 100, metricsJson: nil, isComplete: true
        ))
        #expect(try repo.list(forSession: sessionId).count == 1)
    }

    @Test func weakSpotRepositoryConformsToWeakSpotPersisting() throws {
        let db = try Database.inMemory()
        let repo: any WeakSpotPersisting = WeakSpotRepository(database: db)
        #expect(try repo.listActiveByFrequency(limit: 5).isEmpty)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter PersisterConformanceTests
```

Expected: compile error — `SessionPersisting`, `TurnPersisting`, `WeakSpotPersisting` not found.

- [ ] **Step 3 — Implement persister protocols**

`Sources/Core/Persisters/SessionPersisting.swift`:
```swift
import Foundation

public protocol SessionPersisting: Sendable {
    func create(_ session: Session) throws
    func find(id: UUID) throws -> Session?
    func finalize(id: UUID, endedAt: Date, summary: String?) throws
    func listActive() throws -> [Session]
}
```

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

`Sources/Core/Persisters/WeakSpotPersisting.swift`:
```swift
import Foundation

public protocol WeakSpotPersisting: Sendable {
    func listActiveByFrequency(limit: Int) throws -> [WeakSpot]
}
```

- [ ] **Step 4 — Add conformance extensions**

`Sources/Persistence/Conformances/SessionRepository+SessionPersisting.swift`:
```swift
import Core

extension SessionRepository: SessionPersisting {}
```

`Sources/Persistence/Conformances/TurnRepository+TurnPersisting.swift`:
```swift
import Core

extension TurnRepository: TurnPersisting {}
```

`Sources/Persistence/Conformances/WeakSpotRepository+WeakSpotPersisting.swift`:
```swift
import Core

extension WeakSpotRepository: WeakSpotPersisting {}
```

- [ ] **Step 5 — Confirm green**

```bash
bin/test.sh --filter PersisterConformanceTests
bin/test.sh
```

Expected: 3 new tests pass; full suite still all green.

- [ ] **Step 6 — Commit**

```bash
git add Sources/Core/Persisters/ Sources/Persistence/Conformances/ Tests/PersistenceTests/PersisterConformanceTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core,persistence): add persister protocols + repository conformances"
```

---

## Task 4 — `Fakes` SPM target with all five fake adapters

**Files:**
- Modify: `Package.swift` (add `Fakes` library target)
- Create: `Sources/Fakes/FakeLLMProvider.swift`
- Create: `Sources/Fakes/FakeSTTProvider.swift`
- Create: `Sources/Fakes/FakeTTSProvider.swift`
- Create: `Sources/Fakes/FakeAudioCapture.swift`
- Create: `Sources/Fakes/FakeAudioPlayback.swift`
- Create: `Tests/FakesTests/FakeLLMProviderTests.swift`

- [ ] **Step 1 — Update `Package.swift`**

Locate the existing `products: [ ... ]` and `targets: [ ... ]` arrays in `Package.swift` and add:
- A new `.library(name: "Fakes", targets: ["Fakes"])` entry to `products`.
- A new `.target(name: "Fakes", dependencies: ["Core"])` entry to `targets`.
- A new `.testTarget(name: "FakesTests", dependencies: ["Fakes", "Core"])` entry to `targets`.

The full updated `Package.swift` (replace the file):

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Fakes", targets: ["Fakes"]),
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
        .target(
            name: "Fakes",
            dependencies: ["Core"]
        ),
        .executableTarget(
            name: "SmokeCLI",
            dependencies: ["Core", "Persistence", "Fakes"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core", "Fakes"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "FakesTests", dependencies: ["Fakes", "Core"]),
    ]
)
```

Note that `CoreTests` now also depends on `Fakes` (it'll need fakes for `SessionEngine` tests in Task 8).

- [ ] **Step 2 — Write failing test**

`Tests/FakesTests/FakeLLMProviderTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Fakes

@Suite struct FakeLLMProviderTests {
    @Test func emitsScriptedTokensInOrder() async throws {
        let fake = FakeLLMProvider(scriptedReplies: ["Hello, ", "how can I ", "help today?"])
        var collected = ""
        let stream = try await fake.respond(
            messages: [ChatMessage(role: .user, content: "hi")],
            options: LLMOptions(modelName: "fake")
        )
        for try await chunk in stream {
            collected += chunk
        }
        #expect(collected == "Hello, how can I help today?")
    }

    @Test func recordsReceivedMessages() async throws {
        let fake = FakeLLMProvider(scriptedReplies: ["ok"])
        let messages = [
            ChatMessage(role: .system, content: "be brief"),
            ChatMessage(role: .user, content: "hi"),
        ]
        _ = try await fake.respond(messages: messages, options: LLMOptions(modelName: "fake"))
        let received = await fake.receivedMessages
        #expect(received == messages)
    }

    @Test func throwsAfterScriptedRepliesExhausted() async throws {
        let fake = FakeLLMProvider(scriptedReplies: ["one"])
        _ = try await fake.respond(messages: [], options: LLMOptions(modelName: "fake"))
        await #expect(throws: FakeLLMProviderError.self) {
            _ = try await fake.respond(messages: [], options: LLMOptions(modelName: "fake"))
        }
    }
}
```

- [ ] **Step 3 — Confirm red**

```bash
bin/test.sh --filter FakeLLMProviderTests
```

Expected: compile error — `FakeLLMProvider` not found.

- [ ] **Step 4 — Implement `FakeLLMProvider`**

`Sources/Fakes/FakeLLMProvider.swift`:
```swift
import Foundation
import Core

public actor FakeLLMProvider: LLMProvider {
    private var scripted: [[String]]    // each call uses one inner array of token chunks
    public private(set) var receivedMessages: [ChatMessage] = []

    /// `scriptedReplies` is one full reply (split into token chunks) for the
    /// next `respond` call. Pass an array of arrays for multi-call scripts.
    public init(scriptedReplies: [String]) {
        self.scripted = [scriptedReplies]
    }

    public init(scriptedReplyBatches: [[String]]) {
        self.scripted = scriptedReplyBatches
    }

    public func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error> {
        receivedMessages = messages
        guard !scripted.isEmpty else {
            throw FakeLLMProviderError.scriptExhausted
        }
        let chunks = scripted.removeFirst()
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

public enum FakeLLMProviderError: Error, Equatable {
    case scriptExhausted
}
```

- [ ] **Step 5 — Implement the other fakes (no separate tests — they're trivial)**

`Sources/Fakes/FakeSTTProvider.swift`:
```swift
import Foundation
import Core

public actor FakeSTTProvider: STTProvider {
    private var scripted: [Transcript]
    public private(set) var receivedAudioByteCounts: [Int] = []

    public init(scriptedTranscripts: [Transcript]) {
        self.scripted = scriptedTranscripts
    }

    public init(scriptedTexts: [String], confidence: Double = 0.95) {
        self.scripted = scriptedTexts.map { Transcript(text: $0, confidence: confidence) }
    }

    public func transcribe(audio: Data) async throws -> Transcript {
        receivedAudioByteCounts.append(audio.count)
        guard !scripted.isEmpty else {
            throw FakeSTTProviderError.scriptExhausted
        }
        return scripted.removeFirst()
    }
}

public enum FakeSTTProviderError: Error, Equatable {
    case scriptExhausted
}
```

`Sources/Fakes/FakeTTSProvider.swift`:
```swift
import Foundation
import Core

public actor FakeTTSProvider: TTSProvider {
    public private(set) var synthesizedTexts: [String] = []

    public init() {}

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        synthesizedTexts.append(text)
        // Return a fixed-length placeholder audio buffer.
        return SynthesizedAudio(data: Data(repeating: 0, count: 16), sampleRate: 16000)
    }
}
```

`Sources/Fakes/FakeAudioCapture.swift`:
```swift
import Foundation
import Core

public actor FakeAudioCapture: AudioCapture {
    private var scriptedClips: [Data]
    public private(set) var startCount: Int = 0
    public private(set) var stopCount: Int = 0

    public init(scriptedClips: [Data]) {
        self.scriptedClips = scriptedClips
    }

    /// Convenience: each "clip" is just a placeholder buffer of the given byte count.
    public init(scriptedClipByteCounts: [Int]) {
        self.scriptedClips = scriptedClipByteCounts.map { Data(repeating: 0, count: $0) }
    }

    public func startRecording() async throws {
        startCount += 1
    }

    public func stopRecording() async throws -> Data {
        stopCount += 1
        guard !scriptedClips.isEmpty else {
            throw FakeAudioCaptureError.scriptExhausted
        }
        return scriptedClips.removeFirst()
    }
}

public enum FakeAudioCaptureError: Error, Equatable {
    case scriptExhausted
}
```

`Sources/Fakes/FakeAudioPlayback.swift`:
```swift
import Foundation
import Core

public actor FakeAudioPlayback: AudioPlayback {
    public private(set) var playedClipSizes: [Int] = []

    public init() {}

    public func play(_ audio: SynthesizedAudio) async throws {
        playedClipSizes.append(audio.data.count)
    }
}
```

- [ ] **Step 6 — Confirm green**

```bash
bin/test.sh --filter FakeLLMProviderTests
bin/test.sh
```

Expected: 3 new tests pass; full suite still all green.

- [ ] **Step 7 — Commit**

```bash
git add Package.swift Sources/Fakes/ Tests/FakesTests/
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(fakes): add Fakes target with scripted LLM/STT/TTS/audio fakes"
```

---

## Task 5 — `CoachMarkerParser`

Extracts `[[coach: …]]` markers from LLM output, returning the spoken-only text and a structured list of corrections. The marker grammar is intentionally simple: literal `[[coach:`, then any chars, then literal `]]`. Whitespace inside the marker is preserved.

**Files:**
- Create: `Sources/Core/Engine/CoachMarkerParser.swift`
- Create: `Tests/CoreTests/CoachMarkerParserTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/CoachMarkerParserTests.swift`:
```swift
import Testing
@testable import Core

@Suite struct CoachMarkerParserTests {
    @Test func parsesEmptyTextAsEmptyResult() {
        let result = CoachMarkerParser.parse("")
        #expect(result.spokenText == "")
        #expect(result.corrections.isEmpty)
    }

    @Test func passesThroughTextWithNoMarkers() {
        let result = CoachMarkerParser.parse("Hello there. How are you?")
        #expect(result.spokenText == "Hello there. How are you?")
        #expect(result.corrections.isEmpty)
    }

    @Test func extractsSingleMarkerAndStripsItFromSpokenText() {
        let input = "That's interesting. [[coach: try 'fascinating' instead]] What else?"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "That's interesting.  What else?")
        #expect(result.corrections == [Correction(message: "try 'fascinating' instead")])
    }

    @Test func extractsMultipleMarkersInOrder() {
        let input = "Sure. [[coach: 'sure' is filler]] I'll help. [[coach: 'I will help' is more direct]]"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "Sure.  I'll help. ")
        #expect(result.corrections == [
            Correction(message: "'sure' is filler"),
            Correction(message: "'I will help' is more direct"),
        ])
    }

    @Test func malformedMarkerWithoutClosingIsLeftIntact() {
        let input = "Hi [[coach: never closed and that's OK"
        let result = CoachMarkerParser.parse(input)
        #expect(result.spokenText == "Hi [[coach: never closed and that's OK")
        #expect(result.corrections.isEmpty)
    }

    @Test func emptyMarkerIsRecordedAsEmptyCorrection() {
        let result = CoachMarkerParser.parse("Hi. [[coach: ]] Bye.")
        #expect(result.spokenText == "Hi.  Bye.")
        #expect(result.corrections == [Correction(message: "")])
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter CoachMarkerParserTests
```

Expected: compile error — `CoachMarkerParser`, `Correction` not found.

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/CoachMarkerParser.swift`:
```swift
import Foundation

public struct Correction: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct ParsedReply: Equatable, Sendable {
    public let spokenText: String
    public let corrections: [Correction]

    public init(spokenText: String, corrections: [Correction]) {
        self.spokenText = spokenText
        self.corrections = corrections
    }
}

public enum CoachMarkerParser {
    private static let openMarker = "[[coach:"
    private static let closeMarker = "]]"

    public static func parse(_ input: String) -> ParsedReply {
        var spoken = ""
        var corrections: [Correction] = []
        var remaining = input[...]

        while let openRange = remaining.range(of: openMarker) {
            // Take everything before `[[coach:` as spoken.
            spoken += remaining[..<openRange.lowerBound]
            // Look for the matching `]]` after the open marker.
            let afterOpen = remaining[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: closeMarker) else {
                // Malformed: no closing marker. Restore the whole remainder verbatim.
                spoken += remaining[openRange.lowerBound...]
                return ParsedReply(spokenText: spoken, corrections: corrections)
            }
            let body = afterOpen[..<closeRange.lowerBound]
            corrections.append(Correction(message: body.trimmingCharacters(in: .whitespaces)))
            remaining = afterOpen[closeRange.upperBound...]
        }
        spoken += remaining
        return ParsedReply(spokenText: spoken, corrections: corrections)
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter CoachMarkerParserTests
bin/test.sh
```

Expected: 6 new tests pass; full suite still green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/CoachMarkerParser.swift Tests/CoreTests/CoachMarkerParserTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add CoachMarkerParser for [[coach: …]] extraction"
```

---

## Task 6 — `PersonaBuilder`

Composes the LLM `system` prompt from a `Scenario` + `SessionMode` + active weak spots. The prompt structure is fixed (so the rest of the engine can rely on it):

```
You are roleplaying as: <persona>

Goal: hold a natural English conversation with the user. Do not break character.

[mode-specific instructions]

[weak-spots block, only in coach mode]

Difficulty: <1..5>
```

**Files:**
- Create: `Sources/Core/Engine/PersonaBuilder.swift`
- Create: `Tests/CoreTests/PersonaBuilderTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/PersonaBuilderTests.swift`:
```swift
import Testing
import Foundation
@testable import Core

@Suite struct PersonaBuilderTests {
    private static let scenario = Scenario(
        id: "work-standup-01",
        source: .builtin,
        title: "Standup",
        domain: .work,
        persona: "A no-nonsense engineering manager named Priya.",
        openingLine: "Good morning.",
        difficulty: 2,
        tags: ["meeting"],
        notes: nil
    )

    @Test func includesPersonaDescription() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [])
        #expect(prompt.contains("A no-nonsense engineering manager named Priya."))
    }

    @Test func includesDifficultyLevel() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [])
        #expect(prompt.contains("Difficulty: 2"))
    }

    @Test func flowModeOmitsCoachInstructions() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [])
        #expect(!prompt.contains("[[coach:"))
    }

    @Test func coachModeIncludesMarkerInstructions() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        #expect(prompt.contains("[[coach:"))
        #expect(prompt.contains("]]"))
    }

    @Test func flowModeOmitsWeakSpotsBlockEvenWhenProvided() {
        let ws = WeakSpot(
            id: UUID(), pattern: "uses 'more better'",
            category: .grammar, firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 3, status: .active, exampleTurnIds: []
        )
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .flow, activeWeakSpots: [ws])
        #expect(!prompt.contains("more better"))
    }

    @Test func coachModeIncludesWeakSpotPatterns() {
        let ws1 = WeakSpot(
            id: UUID(), pattern: "uses 'more better'",
            category: .grammar, firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 3, status: .active, exampleTurnIds: []
        )
        let ws2 = WeakSpot(
            id: UUID(), pattern: "stutters on conditionals",
            category: .fluency, firstSeen: Date(), lastSeen: Date(),
            occurrenceCount: 1, status: .active, exampleTurnIds: []
        )
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [ws1, ws2])
        #expect(prompt.contains("uses 'more better'"))
        #expect(prompt.contains("stutters on conditionals"))
    }

    @Test func coachModeWithEmptyWeakSpotsOmitsTheBlockHeader() {
        let prompt = PersonaBuilder.build(scenario: Self.scenario, mode: .coach, activeWeakSpots: [])
        #expect(!prompt.contains("recurring user mistakes"))
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter PersonaBuilderTests
```

Expected: compile error — `PersonaBuilder` not found.

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/PersonaBuilder.swift`:
```swift
import Foundation

public enum PersonaBuilder {
    public static func build(
        scenario: Scenario,
        mode: SessionMode,
        activeWeakSpots: [WeakSpot]
    ) -> String {
        var lines: [String] = []
        lines.append("You are roleplaying as: \(scenario.persona)")
        lines.append("")
        lines.append("Goal: hold a natural English conversation with the user. Do not break character.")
        lines.append("")

        switch mode {
        case .flow:
            lines.append("Conversation style: stay completely in character. Do not correct the user's English even if they make mistakes — that feedback happens after the session ends.")
        case .coach:
            lines.append("Conversation style: stay in character, but if the user makes a clear English mistake, briefly insert a structured correction marker like [[coach: try 'I'd rather' instead of 'I would more like']] right before continuing your reply. Markers are removed before being spoken aloud, so the user only hears your in-character reply.")
            if !activeWeakSpots.isEmpty {
                lines.append("")
                lines.append("Watch especially for these recurring user mistakes:")
                for ws in activeWeakSpots {
                    lines.append("  - \(ws.pattern) (\(ws.category.rawValue))")
                }
            }
        }

        lines.append("")
        lines.append("Difficulty: \(scenario.difficulty)")

        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter PersonaBuilderTests
bin/test.sh
```

Expected: 7 new tests pass; full suite still green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/PersonaBuilder.swift Tests/CoreTests/PersonaBuilderTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add PersonaBuilder for system prompt composition"
```

---

## Task 7 — `ChatHistory` with character-budget truncation

A small in-memory data structure that:
- Always preserves the system message at index 0.
- Appends user/assistant turns.
- When the total content character count exceeds a budget, drops oldest user/assistant turns *in pairs* (oldest user + immediately-following assistant) until under budget.
- Returns the message list to send to the LLM.

V1 doesn't generate a rolling summary of dropped turns — that's TODO for a future plan. The truncation is purely lossy; the persisted `turns` table keeps everything regardless.

**Files:**
- Create: `Sources/Core/Engine/ChatHistory.swift`
- Create: `Tests/CoreTests/ChatHistoryTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/ChatHistoryTests.swift`:
```swift
import Testing
@testable import Core

@Suite struct ChatHistoryTests {
    @Test func startsWithSystemMessageOnly() {
        let history = ChatHistory(systemPrompt: "system", maxCharacterBudget: 1000)
        let msgs = history.messages()
        #expect(msgs.count == 1)
        #expect(msgs.first?.role == .system)
        #expect(msgs.first?.content == "system")
    }

    @Test func appendsUserAndAssistantTurns() {
        var history = ChatHistory(systemPrompt: "s", maxCharacterBudget: 1000)
        history.append(role: .user, content: "u1")
        history.append(role: .assistant, content: "a1")
        let msgs = history.messages()
        #expect(msgs.map(\.role) == [.system, .user, .assistant])
        #expect(msgs.map(\.content) == ["s", "u1", "a1"])
    }

    @Test func dropsOldestUserAssistantPairWhenOverBudget() {
        // Each message is 101 chars (100 'x' + 1 digit). 6 messages = 606. Budget 450.
        // Drop one pair (202 chars) → 404, which is ≤ 450, loop stops.
        var history = ChatHistory(systemPrompt: "system", maxCharacterBudget: 450)
        let big = String(repeating: "x", count: 100)
        history.append(role: .user, content: big + "1")
        history.append(role: .assistant, content: big + "1")
        history.append(role: .user, content: big + "2")
        history.append(role: .assistant, content: big + "2")
        history.append(role: .user, content: big + "3")
        history.append(role: .assistant, content: big + "3")
        let msgs = history.messages()
        // Should have system + 2 pairs; first user/assistant pair dropped.
        #expect(msgs.count == 5)
        #expect(msgs[1].content.hasSuffix("2"))
        #expect(msgs[2].content.hasSuffix("2"))
        #expect(msgs[3].content.hasSuffix("3"))
        #expect(msgs[4].content.hasSuffix("3"))
    }

    @Test func neverDropsTheSystemMessage() {
        var history = ChatHistory(systemPrompt: String(repeating: "S", count: 500), maxCharacterBudget: 100)
        history.append(role: .user, content: "u")
        history.append(role: .assistant, content: "a")
        let msgs = history.messages()
        #expect(msgs.first?.role == .system)
        #expect(msgs.first?.content.count == 500)
    }

    @Test func handlesUnpairedTrailingUserMessage() {
        // System + a1 + u2 + a2 + u3 (no a3 yet). Over budget should drop the leading a1+u2 pair.
        var history = ChatHistory(systemPrompt: "s", maxCharacterBudget: 50)
        let big = String(repeating: "x", count: 30)
        history.append(role: .user, content: "u1" + big)         // pair 1 user
        history.append(role: .assistant, content: "a1" + big)    // pair 1 ai
        history.append(role: .user, content: "u2" + big)         // unpaired trailing user
        let msgs = history.messages()
        // Pair 1 should be dropped; only system + u2 remains.
        #expect(msgs.count == 2)
        #expect(msgs[0].role == .system)
        #expect(msgs[1].content.hasPrefix("u2"))
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter ChatHistoryTests
```

Expected: compile error — `ChatHistory` not found.

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/ChatHistory.swift`:
```swift
import Foundation

public struct ChatHistory: Sendable {
    public let systemPrompt: String
    public let maxCharacterBudget: Int
    private var turns: [ChatMessage] = []   // user/assistant only; system is separate

    public init(systemPrompt: String, maxCharacterBudget: Int) {
        self.systemPrompt = systemPrompt
        self.maxCharacterBudget = maxCharacterBudget
    }

    public mutating func append(role: ChatRole, content: String) {
        precondition(role != .system, "Only user/assistant turns may be appended")
        turns.append(ChatMessage(role: role, content: content))
        truncateIfNeeded()
    }

    public func messages() -> [ChatMessage] {
        [ChatMessage(role: .system, content: systemPrompt)] + turns
    }

    private var turnsCharCount: Int {
        turns.reduce(0) { $0 + $1.content.count }
    }

    private mutating func truncateIfNeeded() {
        while turnsCharCount > maxCharacterBudget && !turns.isEmpty {
            // Drop one pair (user + the assistant that followed) if available;
            // otherwise drop a single leading message.
            turns.removeFirst()
            if let next = turns.first, next.role == .assistant {
                turns.removeFirst()
            }
        }
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter ChatHistoryTests
bin/test.sh
```

Expected: 5 new tests pass; full suite still green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/ChatHistory.swift Tests/CoreTests/ChatHistoryTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add ChatHistory with character-budget truncation"
```

---

## Task 8 — `SessionEngine` actor

The hot loop. Wires STT → LLM → marker-parse → TTS → playback → persist. Implemented as an `actor` so the controller can drive it from any context.

API surface:
- `init(...)` — takes scenario, mode, weak spots, all five providers, both persisters, and an `LLMOptions`.
- `start() async throws` — creates the session row, builds the system prompt, plays the opening line via TTS+playback, persists the opening AI turn.
- `runUserTurn() async throws -> Correction[]` — uses `AudioCapture` to grab the user's audio, transcribes it, persists the user turn, calls the LLM, parses markers, plays the spoken reply, persists the AI turn. Returns any corrections from the AI's reply (empty in flow mode).
- `end(summary: String?) async throws` — finalizes the session row.

**Files:**
- Create: `Sources/Core/Engine/SessionEngine.swift`
- Create: `Tests/CoreTests/SessionEngineTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/CoreTests/SessionEngineTests.swift`:
```swift
import Testing
import Foundation
import Core
import Fakes

/// In-memory persister for tests so we don't depend on Persistence.
final class InMemorySessionPersister: SessionPersisting, @unchecked Sendable {
    var sessions: [UUID: Session] = [:]
    func create(_ session: Session) throws { sessions[session.id] = session }
    func find(id: UUID) throws -> Session? { sessions[id] }
    func finalize(id: UUID, endedAt: Date, summary: String?) throws {
        guard var s = sessions[id] else { return }
        s.endedAt = endedAt; s.summary = summary; s.status = .ended
        sessions[id] = s
    }
    func listActive() throws -> [Session] {
        sessions.values.filter { $0.status == .active }
    }
}

final class InMemoryTurnPersister: TurnPersisting, @unchecked Sendable {
    var turns: [Turn] = []
    func append(_ turn: Turn) throws { turns.append(turn) }
    func list(forSession sessionId: UUID) throws -> [Turn] {
        turns.filter { $0.sessionId == sessionId }.sorted { $0.turnIndex < $1.turnIndex }
    }
    func markIncomplete(id: UUID) throws {
        if let i = turns.firstIndex(where: { $0.id == id }) { turns[i].isComplete = false }
    }
    func updateMetricsJson(turnId: UUID, json: String) throws {
        if let i = turns.firstIndex(where: { $0.id == turnId }) { turns[i].metricsJson = json }
    }
}

@Suite struct SessionEngineTests {
    private static let scenario = Scenario(
        id: "test-01", source: .builtin, title: "Test", domain: .work,
        persona: "Test persona.",
        openingLine: "Hi, how are you?",
        difficulty: 2, tags: [], notes: nil
    )

    private static func makeEngine(
        mode: SessionMode = .flow,
        scriptedReplies: [[String]] = [["I'm well, thanks!"]],
        scriptedTranscripts: [String] = [],
        scriptedClipByteCounts: [Int] = []
    ) -> (SessionEngine, InMemorySessionPersister, InMemoryTurnPersister, FakeAudioPlayback, FakeTTSProvider) {
        let sessionPersister = InMemorySessionPersister()
        let turnPersister = InMemoryTurnPersister()
        let llm = FakeLLMProvider(scriptedReplyBatches: scriptedReplies)
        let stt = FakeSTTProvider(scriptedTexts: scriptedTranscripts)
        let tts = FakeTTSProvider()
        let capture = FakeAudioCapture(scriptedClipByteCounts: scriptedClipByteCounts)
        let playback = FakeAudioPlayback()
        let engine = SessionEngine(
            scenario: scenario,
            mode: mode,
            activeWeakSpots: [],
            llm: llm,
            stt: stt,
            tts: tts,
            audioCapture: capture,
            audioPlayback: playback,
            sessionPersister: sessionPersister,
            turnPersister: turnPersister,
            voice: Voice(id: "default", displayName: "Default"),
            llmOptions: LLMOptions(modelName: "fake")
        )
        return (engine, sessionPersister, turnPersister, playback, tts)
    }

    @Test func startCreatesSessionAndPlaysOpeningLineAndPersistsAITurn() async throws {
        let (engine, sessions, turns, playback, tts) = Self.makeEngine()
        try await engine.start()
        #expect(sessions.sessions.count == 1)
        let session = sessions.sessions.values.first!
        #expect(session.scenarioId == "test-01")
        #expect(session.status == .active)
        let allTurns = try turns.list(forSession: session.id)
        #expect(allTurns.count == 1)
        #expect(allTurns[0].speaker == .ai)
        #expect(allTurns[0].text == "Hi, how are you?")
        let played = await playback.playedClipSizes
        #expect(played.count == 1)
        let synthed = await tts.synthesizedTexts
        #expect(synthed == ["Hi, how are you?"])
    }

    @Test func runUserTurnPersistsBothUserAndAITurnsInOrder() async throws {
        let (engine, sessions, turns, _, _) = Self.makeEngine(
            scriptedReplies: [["I'm well, thanks!"]],
            scriptedTranscripts: ["I'm fine, how about you?"],
            scriptedClipByteCounts: [1000]
        )
        try await engine.start()
        _ = try await engine.runUserTurn()
        let session = sessions.sessions.values.first!
        let all = try turns.list(forSession: session.id)
        #expect(all.count == 3)  // ai-opening, user, ai-reply
        #expect(all[0].speaker == .ai)   // opening
        #expect(all[1].speaker == .user)
        #expect(all[1].text == "I'm fine, how about you?")
        #expect(all[2].speaker == .ai)
        #expect(all[2].text == "I'm well, thanks!")
        // Indices are strictly increasing.
        #expect(all.map(\.turnIndex) == [0, 1, 2])
    }

    @Test func coachModeReturnsCorrectionsAndStripsThemFromTTS() async throws {
        let scripted = [["I see! [[coach: try 'I think' instead of 'I am thinking']]"]]
        let (engine, _, turns, _, tts) = Self.makeEngine(
            mode: .coach,
            scriptedReplies: scripted,
            scriptedTranscripts: ["I am thinking that..."],
            scriptedClipByteCounts: [1000]
        )
        try await engine.start()
        let corrections = try await engine.runUserTurn()
        #expect(corrections == [Correction(message: "try 'I think' instead of 'I am thinking'")])
        // The persisted AI turn keeps the full original text (for the debrief later);
        // TTS receives only the spoken portion.
        let synthed = await tts.synthesizedTexts
        // synthed[0] is the opening line; synthed[1] is the AI reply, marker-stripped
        #expect(synthed.count == 2)
        #expect(synthed[1] == "I see! ")
        // Persisted text includes the marker so the debrief can show it.
        let session = (try await engine.sessionForTesting())!
        let all = try turns.list(forSession: session.id)
        let aiReply = all.last!
        #expect(aiReply.text.contains("[[coach:"))
    }

    @Test func endFinalizesSessionWithSummary() async throws {
        let (engine, sessions, _, _, _) = Self.makeEngine()
        try await engine.start()
        try await engine.end(summary: "Test session.")
        let session = sessions.sessions.values.first!
        #expect(session.status == .ended)
        #expect(session.summary == "Test session.")
        #expect(session.endedAt != nil)
    }

    @Test func systemPromptIncludesPersonaAndModeInstructions() async throws {
        let scripted = [["ok"]]
        let (engine, _, _, _, _) = Self.makeEngine(scriptedReplies: scripted)
        let llm = await engine.llmForTesting() as! FakeLLMProvider
        try await engine.start()
        let messages = await llm.receivedMessages
        // Opening-line generation actually doesn't go through the LLM (it's spoken directly
        // from scenario.openingLine), so receivedMessages should still be empty.
        #expect(messages.isEmpty)

        // Now run a turn so the LLM is invoked.
        let (engine2, _, _, _, _) = Self.makeEngine(
            scriptedReplies: scripted,
            scriptedTranscripts: ["hi"],
            scriptedClipByteCounts: [100]
        )
        try await engine2.start()
        _ = try await engine2.runUserTurn()
        let llm2 = await engine2.llmForTesting() as! FakeLLMProvider
        let msgs = await llm2.receivedMessages
        #expect(msgs.first?.role == .system)
        #expect(msgs.first?.content.contains("Test persona.") == true)
        #expect(msgs.contains { $0.role == .user && $0.content == "hi" })
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter SessionEngineTests
```

Expected: compile error — `SessionEngine` not found.

- [ ] **Step 3 — Implement**

`Sources/Core/Engine/SessionEngine.swift`:
```swift
import Foundation

public actor SessionEngine {
    public let scenario: Scenario
    public let mode: SessionMode
    public let activeWeakSpots: [WeakSpot]
    public let voice: Voice
    public let llmOptions: LLMOptions

    private let llm: LLMProvider
    private let stt: STTProvider
    private let tts: TTSProvider
    private let audioCapture: AudioCapture
    private let audioPlayback: AudioPlayback
    private let sessionPersister: SessionPersisting
    private let turnPersister: TurnPersisting

    private var sessionId: UUID?
    private var nextTurnIndex: Int = 0
    private var history: ChatHistory?

    public static let defaultHistoryBudget = 12_000  // characters; ~3000 tokens at ~4 chars/token

    public init(
        scenario: Scenario,
        mode: SessionMode,
        activeWeakSpots: [WeakSpot],
        llm: LLMProvider,
        stt: STTProvider,
        tts: TTSProvider,
        audioCapture: AudioCapture,
        audioPlayback: AudioPlayback,
        sessionPersister: SessionPersisting,
        turnPersister: TurnPersisting,
        voice: Voice,
        llmOptions: LLMOptions
    ) {
        self.scenario = scenario
        self.mode = mode
        self.activeWeakSpots = activeWeakSpots
        self.llm = llm
        self.stt = stt
        self.tts = tts
        self.audioCapture = audioCapture
        self.audioPlayback = audioPlayback
        self.sessionPersister = sessionPersister
        self.turnPersister = turnPersister
        self.voice = voice
        self.llmOptions = llmOptions
    }

    /// Creates the session row, sets up the chat history with the system prompt,
    /// speaks and persists the opening line as an AI turn.
    public func start() async throws {
        let id = UUID()
        sessionId = id
        let now = Date()
        let session = Session(
            id: id,
            scenarioId: scenario.id,
            startedAt: now,
            endedAt: nil,
            mode: mode,
            status: .active,
            summary: nil,
            personaSnapshot: scenario.persona
        )
        try sessionPersister.create(session)

        let systemPrompt = PersonaBuilder.build(
            scenario: scenario,
            mode: mode,
            activeWeakSpots: activeWeakSpots
        )
        history = ChatHistory(systemPrompt: systemPrompt, maxCharacterBudget: Self.defaultHistoryBudget)

        try await speakAndPersist(text: scenario.openingLine, isOpening: true)
    }

    /// Runs one full turn: capture user audio, transcribe, persist user turn,
    /// call LLM, parse markers, speak the spoken portion, persist AI turn.
    /// Returns any corrections extracted from the AI's reply.
    @discardableResult
    public func runUserTurn() async throws -> [Correction] {
        guard sessionId != nil, history != nil else {
            throw SessionEngineError.notStarted
        }

        try await audioCapture.startRecording()
        let audio = try await audioCapture.stopRecording()
        let userStart = Date()
        let transcript = try await stt.transcribe(audio: audio)

        try persistUserTurn(text: transcript.text, audioByteCount: audio.count, startedAt: userStart)
        history!.append(role: .user, content: transcript.text)

        let aiStart = Date()
        let stream = try await llm.respond(messages: history!.messages(), options: llmOptions)
        var fullReply = ""
        for try await chunk in stream {
            fullReply += chunk
        }
        let parsed = CoachMarkerParser.parse(fullReply)
        history!.append(role: .assistant, content: fullReply)

        try await speakAndPersistAIReply(
            spokenText: parsed.spokenText,
            originalText: fullReply,
            startedAt: aiStart
        )

        return parsed.corrections
    }

    /// Finalizes the session row.
    public func end(summary: String?) async throws {
        guard let id = sessionId else { throw SessionEngineError.notStarted }
        try sessionPersister.finalize(id: id, endedAt: Date(), summary: summary)
    }

    // Test helpers — visible to tests via @testable import or direct call.
    public func sessionForTesting() throws -> Session? {
        guard let id = sessionId else { return nil }
        return try sessionPersister.find(id: id)
    }

    public func llmForTesting() -> LLMProvider {
        llm
    }

    // MARK: - private

    private func speakAndPersist(text: String, isOpening: Bool) async throws {
        let start = Date()
        let audio = try await tts.synthesize(text: text, voice: voice)
        try await audioPlayback.play(audio)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        try persistAITurn(text: text, durationMs: elapsed, startedAt: start)
        // The opening line isn't fed back into history as an "assistant" message
        // because the LLM didn't generate it. Putting it in would mislead the model.
        if !isOpening {
            history?.append(role: .assistant, content: text)
        }
    }

    private func speakAndPersistAIReply(spokenText: String, originalText: String, startedAt: Date) async throws {
        let synthStart = Date()
        let audio = try await tts.synthesize(text: spokenText, voice: voice)
        try await audioPlayback.play(audio)
        let elapsed = Int(Date().timeIntervalSince(synthStart) * 1000)
        try persistAITurn(text: originalText, durationMs: elapsed, startedAt: startedAt)
    }

    private func persistAITurn(text: String, durationMs: Int, startedAt: Date) throws {
        guard let id = sessionId else { throw SessionEngineError.notStarted }
        let turn = Turn(
            id: UUID(),
            sessionId: id,
            turnIndex: nextTurnIndex,
            speaker: .ai,
            text: text,
            audioPath: nil,
            startedAt: startedAt,
            durationMs: durationMs,
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(turn)
        nextTurnIndex += 1
    }

    private func persistUserTurn(text: String, audioByteCount: Int, startedAt: Date) throws {
        guard let id = sessionId else { throw SessionEngineError.notStarted }
        let turn = Turn(
            id: UUID(),
            sessionId: id,
            turnIndex: nextTurnIndex,
            speaker: .user,
            text: text,
            audioPath: nil,    // wiring to disk audio happens in Plan 5
            startedAt: startedAt,
            durationMs: 0,     // will be filled in once AudioCapture provides duration in Plan 5
            metricsJson: nil,
            isComplete: true
        )
        try turnPersister.append(turn)
        nextTurnIndex += 1
    }
}

public enum SessionEngineError: Error, Equatable {
    case notStarted
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter SessionEngineTests
bin/test.sh
```

Expected: 5 new tests pass; full suite still green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Core/Engine/SessionEngine.swift Tests/CoreTests/SessionEngineTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(core): add SessionEngine actor for turn-loop orchestration"
```

---

## Task 9 — SmokeCLI: real fake-driven session demo

Replace the Plan 1 SmokeCLI demo with one that drives `SessionEngine` end-to-end using fakes, persisting to a real on-disk SQLite DB. Proves all the layers wire together.

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

    // Scripted fakes — represent two user turns and the AI replies they elicit.
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
```

- [ ] **Step 2 — Build and run**

```bash
swift build
swift run smoke-cli
```

Expected output (approximate; details may vary):
```
→ Opening DB at /tmp/eng-assistant-engine-smoke.sqlite
→ Loading scenario
  scenario: Daily Engineering Standup
→ Starting session
→ Running user turn 1
→ Running user turn 2
→ Ending session

=== Result ===
Session status: ended
Summary: Standup practice via fakes.
Turns: 5
  [0] ai: Good morning. What did you finish yesterday, and what are you picking up today?
  [1] user: Yesterday I finished the auth refactor. Today I'm picking up the rate-limiter.
  [2] ai: I see — auth refactor done. Any blockers I should know about?
  [3] user: No blockers, but I'd like a review on the auth PR before EOD.
  [4] ai: Got it. Let's plan the review for after standup.
TTS calls: 3
Audio playbacks: 3

✓ engine smoke OK
```

Verify exit code 0.

- [ ] **Step 3 — Run full test suite**

```bash
bin/test.sh 2>&1 | tail -5
```

Expected: every test green.

- [ ] **Step 4 — Commit**

```bash
git add Sources/SmokeCLI/main.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(smoke): drive SessionEngine end-to-end with fakes + on-disk DB"
```

---

## Plan 2 Self-Review

| Spec / Plan-1 hand-off requirement | Covered by |
|---|---|
| Adapter protocols (`STTProvider`, `LLMProvider`, `TTSProvider`, `AudioCapture`, `AudioPlayback`) in Core | Tasks 1–2 |
| Persister protocols + repository conformances | Task 3 |
| Fake adapters usable from both tests and CLI | Task 4 |
| `[[coach: …]]` marker parser (tolerant of malformed) | Task 5 |
| `PersonaBuilder` composes system prompt with mode + weak spots | Task 6 |
| History truncation by character budget | Task 7 |
| `SessionEngine` actor: start, run turn, end | Task 8 |
| Coach mode markers stripped from TTS but preserved in DB | Task 8 (coach-mode test) |
| End-to-end demo proving everything wires together | Task 9 |

**Out of scope (defer to later plans):**
- Real OllamaLLM, WhisperLocalSTT, PiperTTS implementations → Plan 4
- Real AVAudioEngine capture / AVAudioPlayer playback → Plan 5
- MetricsAnalyzer, WeakSpotExtractor, CoachingEngine → Plan 3
- Rolling summarization for truncated history → future plan
- Audio path persistence (turns.audio_path stays nil for now) → Plan 5
- Turn duration measurement for user turns → Plan 5

---

## Definition of Done (Plan 2)

- `swift build` succeeds with no warnings.
- `bin/test.sh` runs ~70 tests across ~22 suites and they all pass.
- `swift run smoke-cli` produces the engine-driven demo and exits 0.
- One git commit per task (9 commits).
- No file-internal placeholders, TODOs, or unfinished functions.
- `Core` still has zero dependency on `Persistence`/AppKit/SwiftUI/GRDB.
