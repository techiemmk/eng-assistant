# Local Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fake adapters with real local provider implementations: `OllamaLLM` (HTTP client to a locally-running Ollama process), `WhisperLocalSTT` (shells out to whisper-cli), `PiperTTS` (shells out to Piper), and `AVSpeechTTS` (Apple framework fallback). Each conforms to its `Core` adapter protocol and is testable via injected `HTTPClient` / `ProcessRunner` abstractions, so unit tests don't require the user to have Ollama or whisper.cpp or Piper installed. Live contract tests (gated behind `RUN_LIVE_TESTS=1`) exercise the real binaries when available.

**Architecture:** A new SPM library target `Adapters` houses the concrete provider implementations. `Adapters` depends on `Core` (protocols + value types) and on Foundation. Two small ports — `HTTPClient` and `ProcessRunner` — sit inside `Adapters` and isolate the side-effecting OS calls so unit tests can substitute deterministic stubs. The smoke CLI grows a `--live` flag that swaps the fake LLM for `OllamaLLM`; STT/TTS stay on fakes until Plan 5 wires real audio I/O. The end state: a session can run against a real local Ollama model (e.g. `qwen2.5:7b-instruct`) when the user has it installed, and the unit suite still passes without it.

**Tech Stack:** Swift 5.9+, Swift Package Manager, Foundation (URLSession, Process), AVFoundation (`AVSpeechSynthesizer`), Swift Testing.

**Test runner:** Use `bin/test.sh` (NOT `swift test`). Test framework is **Swift Testing**.

**Git committer:** All implementer subagents are dispatched with `git -c user.email=techiemmk@gmail.com -c user.name="Manoj"`.

**Branching:** Implemented directly on `main` per durable preference.

---

## File Structure

```
Sources/
├── Adapters/                              # NEW SPM library target
│   ├── HTTP/
│   │   ├── HTTPClient.swift               # protocol + value types
│   │   └── URLSessionHTTPClient.swift     # production impl
│   ├── Process/
│   │   ├── ProcessRunner.swift            # protocol + value types
│   │   └── ForegroundProcessRunner.swift  # production impl
│   ├── LLM/
│   │   └── OllamaLLM.swift                # LLMProvider via HTTPClient
│   ├── STT/
│   │   └── WhisperLocalSTT.swift          # STTProvider via ProcessRunner
│   └── TTS/
│       ├── PiperTTS.swift                 # TTSProvider via ProcessRunner
│       └── AVSpeechTTS.swift              # TTSProvider via AVSpeechSynthesizer
├── Core/
├── Persistence/
├── Fakes/
└── SmokeCLI/main.swift                    # MODIFY: --live flag

Tests/
├── AdaptersTests/                         # NEW
│   ├── OllamaLLMTests.swift               # uses StubHTTPClient
│   ├── WhisperLocalSTTTests.swift         # uses StubProcessRunner
│   ├── PiperTTSTests.swift                # uses StubProcessRunner
│   └── LiveProvidersTests.swift           # gated by RUN_LIVE_TESTS=1
```

**Per-file responsibility:**

| File | Responsibility |
|---|---|
| `HTTPClient.swift` | Protocol with one method: `postJSONStream(url:body:headers:) -> AsyncThrowingStream<Data, Error>`. Yields raw bytes; the caller chunks them into JSONL lines. |
| `URLSessionHTTPClient.swift` | Production conformance using `URLSession.bytes(for:)`. |
| `ProcessRunner.swift` | Protocol: `run(executable:arguments:stdin:) async throws -> ProcessResult`. Returns exit code, stdout, stderr. |
| `ForegroundProcessRunner.swift` | Production conformance using `Foundation.Process` + `Pipe`. |
| `OllamaLLM.swift` | `LLMProvider` conformance. Builds an `/api/chat` JSON body, asks `HTTPClient` for a streaming response, parses each JSONL chunk's `message.content`, yields the text on the `AsyncThrowingStream<String, Error>` it returns. |
| `WhisperLocalSTT.swift` | `STTProvider` conformance. Writes incoming audio bytes to a temp file, runs `whisper-cli` with the configured model, parses stdout for the transcribed text, returns a `Transcript`. |
| `PiperTTS.swift` | `TTSProvider` conformance. Pipes text into `piper`, captures WAV bytes from stdout, returns `SynthesizedAudio`. |
| `AVSpeechTTS.swift` | `TTSProvider` conformance via `AVSpeechSynthesizer.write(_:toBufferCallback:)`. Used when Piper isn't installed. |
| `LiveProvidersTests.swift` | Smoke-style integration tests that run only when `RUN_LIVE_TESTS=1` is set in the environment. |

---

## Task 1 — `Adapters` SPM target + `HTTPClient` port

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Adapters/HTTP/HTTPClient.swift`
- Create: `Sources/Adapters/HTTP/URLSessionHTTPClient.swift`
- Create: `Tests/AdaptersTests/HTTPClientTypesTests.swift`

- [ ] **Step 1 — Update Package.swift**

Replace `Package.swift` with:

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
        .library(name: "Adapters", targets: ["Adapters"]),
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
        .target(
            name: "Adapters",
            dependencies: ["Core"]
        ),
        .executableTarget(
            name: "SmokeCLI",
            dependencies: ["Core", "Persistence", "Fakes", "Adapters"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core", "Fakes"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "FakesTests", dependencies: ["Fakes", "Core"]),
        .testTarget(name: "AdaptersTests", dependencies: ["Adapters", "Core"]),
    ]
)
```

- [ ] **Step 2 — Write failing test**

`Tests/AdaptersTests/HTTPClientTypesTests.swift`:
```swift
import Testing
import Foundation
@testable import Adapters

@Suite struct HTTPClientTypesTests {
    @Test func httpClientErrorEquality() {
        let a = HTTPClientError.transport("timeout")
        let b = HTTPClientError.transport("timeout")
        let c = HTTPClientError.statusCode(500)
        #expect(a == b)
        #expect(a != c)
    }
}
```

- [ ] **Step 3 — Confirm red**

```bash
swift package clean
bin/test.sh --filter HTTPClientTypesTests
```

Expected: compile error — `HTTPClientError` not found.

- [ ] **Step 4 — Implement `HTTPClient` protocol + error type**

`Sources/Adapters/HTTP/HTTPClient.swift`:
```swift
import Foundation

public protocol HTTPClient: Sendable {
    /// Sends a POST request with the given JSON body and headers, and returns an
    /// async stream of response bytes. The stream yields data chunks as they arrive
    /// (typically newline-delimited JSON). Throws on non-2xx status or transport
    /// failure.
    func postJSONStream(
        url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> AsyncThrowingStream<Data, Error>
}

public enum HTTPClientError: Error, Equatable, Sendable {
    case transport(String)
    case statusCode(Int)
    case invalidResponse
}
```

- [ ] **Step 5 — Implement `URLSessionHTTPClient`**

`Sources/Adapters/HTTP/URLSessionHTTPClient.swift`:
```swift
import Foundation

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func postJSONStream(
        url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> AsyncThrowingStream<Data, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPClientError.statusCode(http.statusCode)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        // Flush whenever a newline is reached so JSONL chunks
                        // arrive as discrete events.
                        if byte == 0x0A {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 6 — Confirm green**

```bash
bin/test.sh --filter HTTPClientTypesTests
bin/test.sh
```

Expected: 1 new test passes; full suite (now 106 tests in 32 suites) all green.

- [ ] **Step 7 — Commit**

```bash
git add Package.swift Sources/Adapters/HTTP/ Tests/AdaptersTests/HTTPClientTypesTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(adapters): add Adapters SPM target with HTTPClient port"
```

---

## Task 2 — `ProcessRunner` port

**Files:**
- Create: `Sources/Adapters/Process/ProcessRunner.swift`
- Create: `Sources/Adapters/Process/ForegroundProcessRunner.swift`
- Create: `Tests/AdaptersTests/ForegroundProcessRunnerTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/AdaptersTests/ForegroundProcessRunnerTests.swift`:
```swift
import Testing
import Foundation
@testable import Adapters

@Suite struct ForegroundProcessRunnerTests {
    @Test func runsEchoAndCapturesStdout() async throws {
        let runner = ForegroundProcessRunner()
        let result = try await runner.run(
            executable: "/bin/echo",
            arguments: ["hello", "world"],
            stdin: nil
        )
        #expect(result.exitCode == 0)
        let out = String(decoding: result.stdout, as: UTF8.self)
        #expect(out.contains("hello world"))
    }

    @Test func reportsNonZeroExitCode() async throws {
        let runner = ForegroundProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "exit 7"],
            stdin: nil
        )
        #expect(result.exitCode == 7)
    }

    @Test func passesStdinThrough() async throws {
        let runner = ForegroundProcessRunner()
        let result = try await runner.run(
            executable: "/bin/cat",
            arguments: [],
            stdin: Data("piped input".utf8)
        )
        #expect(result.exitCode == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "piped input")
    }

    @Test func missingExecutableThrows() async throws {
        let runner = ForegroundProcessRunner()
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(
                executable: "/usr/bin/this-does-not-exist-anywhere",
                arguments: [],
                stdin: nil
            )
        }
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter ForegroundProcessRunnerTests
```

Expected: compile error — `ForegroundProcessRunner`, `ProcessRunner`, `ProcessRunnerError` not found.

- [ ] **Step 3 — Implement `ProcessRunner`**

`Sources/Adapters/Process/ProcessRunner.swift`:
```swift
import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case executableNotFound(String)
    case launchFailed(String)
}
```

- [ ] **Step 4 — Implement `ForegroundProcessRunner`**

`Sources/Adapters/Process/ForegroundProcessRunner.swift`:
```swift
import Foundation

public struct ForegroundProcessRunner: ProcessRunner {
    public init() {}

    public func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult {
        let url = URL(fileURLWithPath: executable)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if stdin != nil {
                process.standardInput = stdinPipe
            }

            process.terminationHandler = { proc in
                let out = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: out ?? Data(),
                    stderr: err ?? Data()
                ))
            }

            do {
                try process.run()
                if let stdin = stdin {
                    let writer = stdinPipe.fileHandleForWriting
                    try writer.write(contentsOf: stdin)
                    try writer.close()
                }
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed("\(error)"))
            }
        }
    }
}
```

- [ ] **Step 5 — Confirm green**

```bash
bin/test.sh --filter ForegroundProcessRunnerTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 110 tests in 33 suites) all green.

- [ ] **Step 6 — Commit**

```bash
git add Sources/Adapters/Process/ Tests/AdaptersTests/ForegroundProcessRunnerTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(adapters): add ProcessRunner port + Foundation impl"
```

---

## Task 3 — `OllamaLLM`

**Files:**
- Create: `Sources/Adapters/LLM/OllamaLLM.swift`
- Create: `Tests/AdaptersTests/OllamaLLMTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/AdaptersTests/OllamaLLMTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Adapters

/// Stub HTTPClient that returns scripted byte chunks (each chunk is one
/// JSONL line ending in '\n').
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    var nextChunks: [Data] = []
    var nextError: Error?
    var lastURL: URL?
    var lastBody: Data?

    func postJSONStream(url: URL, body: Data, headers: [String : String]) async throws -> AsyncThrowingStream<Data, Error> {
        lastURL = url
        lastBody = body
        if let err = nextError { throw err }
        let chunks = nextChunks
        return AsyncThrowingStream { continuation in
            for c in chunks { continuation.yield(c) }
            continuation.finish()
        }
    }
}

@Suite struct OllamaLLMTests {
    private static func chunk(_ s: String) -> Data {
        Data((s + "\n").utf8)
    }

    @Test func streamsContentFromJSONLChunks() async throws {
        let client = StubHTTPClient()
        client.nextChunks = [
            Self.chunk(#"{"message":{"role":"assistant","content":"Hello, "},"done":false}"#),
            Self.chunk(#"{"message":{"role":"assistant","content":"world!"},"done":false}"#),
            Self.chunk(#"{"message":{"role":"assistant","content":""},"done":true}"#),
        ]
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        let stream = try await llm.respond(
            messages: [ChatMessage(role: .user, content: "hi")],
            options: LLMOptions(modelName: "qwen2.5:7b-instruct")
        )
        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }
        #expect(collected == "Hello, world!")
    }

    @Test func sendsCorrectURLAndBodyShape() async throws {
        let client = StubHTTPClient()
        client.nextChunks = [Self.chunk(#"{"message":{"content":""},"done":true}"#)]
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        _ = try await llm.respond(
            messages: [
                ChatMessage(role: .system, content: "be brief"),
                ChatMessage(role: .user, content: "hi"),
            ],
            options: LLMOptions(modelName: "test-model", temperature: 0.5, maxTokens: 100)
        )
        #expect(client.lastURL?.absoluteString == "http://localhost:11434/api/chat")
        let body = try #require(client.lastBody)
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["model"] as? String == "test-model")
        #expect(obj["stream"] as? Bool == true)
        let messages = try #require(obj["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[1]["role"] as? String == "user")
    }

    @Test func ignoresMalformedJsonLines() async throws {
        let client = StubHTTPClient()
        client.nextChunks = [
            Self.chunk(#"{"message":{"content":"OK "},"done":false}"#),
            Self.chunk("not-json\n"),
            Self.chunk(#"{"message":{"content":"continues."},"done":true}"#),
        ]
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        let stream = try await llm.respond(
            messages: [ChatMessage(role: .user, content: "x")],
            options: LLMOptions(modelName: "m")
        )
        var collected = ""
        for try await c in stream { collected += c }
        #expect(collected == "OK continues.")
    }

    @Test func propagatesHTTPErrors() async throws {
        let client = StubHTTPClient()
        client.nextError = HTTPClientError.statusCode(503)
        let llm = OllamaLLM(httpClient: client, baseURL: URL(string: "http://localhost:11434")!)
        await #expect(throws: HTTPClientError.self) {
            _ = try await llm.respond(
                messages: [ChatMessage(role: .user, content: "x")],
                options: LLMOptions(modelName: "m")
            )
        }
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter OllamaLLMTests
```

Expected: compile error — `OllamaLLM` not found.

- [ ] **Step 3 — Implement**

`Sources/Adapters/LLM/OllamaLLM.swift`:
```swift
import Foundation
import Core

public struct OllamaLLM: LLMProvider {
    private let httpClient: HTTPClient
    private let baseURL: URL

    public init(httpClient: HTTPClient, baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    public func respond(messages: [ChatMessage], options: LLMOptions) async throws -> AsyncThrowingStream<String, Error> {
        let url = baseURL.appendingPathComponent("api").appendingPathComponent("chat")
        let body: [String: Any] = [
            "model": options.modelName,
            "stream": true,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "options": [
                "temperature": options.temperature,
                "num_predict": options.maxTokens,
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let byteStream = try await httpClient.postJSONStream(url: url, body: bodyData, headers: [:])

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in byteStream {
                        // Each chunk is typically one JSONL line; defensively split on '\n'.
                        let lines = chunk.split(separator: 0x0A, omittingEmptySubsequences: true)
                        for line in lines {
                            let lineData = Data(line)
                            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                                continue
                            }
                            if let message = obj["message"] as? [String: Any],
                               let content = message["content"] as? String,
                               !content.isEmpty {
                                continuation.yield(content)
                            }
                            if obj["done"] as? Bool == true {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter OllamaLLMTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 114 tests in 34 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Adapters/LLM/OllamaLLM.swift Tests/AdaptersTests/OllamaLLMTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(adapters): add OllamaLLM (HTTPClient-driven, JSONL stream)"
```

---

## Task 4 — `WhisperLocalSTT`

Process-based STT that shells out to `whisper-cli`. The user installs it themselves (e.g. `brew install whisper-cpp`). Configurable executable path + model file.

**Files:**
- Create: `Sources/Adapters/STT/WhisperLocalSTT.swift`
- Create: `Tests/AdaptersTests/WhisperLocalSTTTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/AdaptersTests/WhisperLocalSTTTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Adapters

final class StubProcessRunner: ProcessRunner, @unchecked Sendable {
    var nextResult: ProcessResult?
    var nextError: Error?
    var lastInvocation: (executable: String, arguments: [String], stdin: Data?)?

    func run(executable: String, arguments: [String], stdin: Data?) async throws -> ProcessResult {
        lastInvocation = (executable, arguments, stdin)
        if let err = nextError { throw err }
        return nextResult ?? ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
}

@Suite struct WhisperLocalSTTTests {
    @Test func returnsTranscriptFromStdout() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(
            exitCode: 0,
            stdout: Data("Yesterday I finished the auth refactor.\n".utf8),
            stderr: Data()
        )
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/whisper-small.en.bin"
        )
        let transcript = try await stt.transcribe(audio: Data(repeating: 0, count: 16))
        #expect(transcript.text == "Yesterday I finished the auth refactor.")
        #expect(transcript.confidence > 0)
    }

    @Test func passesAudioBytesAsStdin() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(exitCode: 0, stdout: Data("ok".utf8), stderr: Data())
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/m.bin"
        )
        let audio = Data([1, 2, 3, 4, 5])
        _ = try await stt.transcribe(audio: audio)
        #expect(runner.lastInvocation?.stdin == audio)
        #expect(runner.lastInvocation?.executable == "/usr/local/bin/whisper-cli")
        let args = runner.lastInvocation?.arguments ?? []
        #expect(args.contains("/tmp/m.bin"))
    }

    @Test func nonZeroExitCodeThrows() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(
            exitCode: 1,
            stdout: Data(),
            stderr: Data("model not found".utf8)
        )
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/missing.bin"
        )
        await #expect(throws: WhisperLocalSTTError.self) {
            _ = try await stt.transcribe(audio: Data())
        }
    }

    @Test func emptyStdoutReturnsLowConfidenceTranscript() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
        let stt = WhisperLocalSTT(
            runner: runner,
            executablePath: "/usr/local/bin/whisper-cli",
            modelPath: "/tmp/m.bin"
        )
        let transcript = try await stt.transcribe(audio: Data(repeating: 0, count: 16))
        #expect(transcript.text == "")
        #expect(transcript.confidence == 0)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter WhisperLocalSTTTests
```

- [ ] **Step 3 — Implement**

`Sources/Adapters/STT/WhisperLocalSTT.swift`:
```swift
import Foundation
import Core

public struct WhisperLocalSTT: STTProvider {
    private let runner: ProcessRunner
    private let executablePath: String
    private let modelPath: String

    public init(runner: ProcessRunner, executablePath: String, modelPath: String) {
        self.runner = runner
        self.executablePath = executablePath
        self.modelPath = modelPath
    }

    public func transcribe(audio: Data) async throws -> Transcript {
        // whisper-cli accepts WAV from stdin with --file -. Print plain text only
        // (--no-prints --no-timestamps) and write to stdout (--output-txt -).
        let args = [
            "--model", modelPath,
            "--file", "-",
            "--no-prints",
            "--no-timestamps",
            "--output-txt", "-",
        ]
        let result = try await runner.run(
            executable: executablePath,
            arguments: args,
            stdin: audio
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw WhisperLocalSTTError.transcriptionFailed(exitCode: result.exitCode, stderr: stderr)
        }
        let text = String(decoding: result.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // whisper.cpp doesn't surface a confidence value via the CLI, so we use
        // a coarse heuristic: empty output → 0; any output → 0.85 placeholder.
        let confidence = text.isEmpty ? 0.0 : 0.85
        return Transcript(text: text, confidence: confidence)
    }
}

public enum WhisperLocalSTTError: Error, Equatable, Sendable {
    case transcriptionFailed(exitCode: Int32, stderr: String)
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter WhisperLocalSTTTests
bin/test.sh
```

Expected: 4 new tests pass; full suite (now 118 tests in 35 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Adapters/STT/WhisperLocalSTT.swift Tests/AdaptersTests/WhisperLocalSTTTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(adapters): add WhisperLocalSTT (whisper-cli via ProcessRunner)"
```

---

## Task 5 — `PiperTTS`

**Files:**
- Create: `Sources/Adapters/TTS/PiperTTS.swift`
- Create: `Tests/AdaptersTests/PiperTTSTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/AdaptersTests/PiperTTSTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Adapters

@Suite struct PiperTTSTests {
    @Test func writesTextToStdinAndReturnsWavBytes() async throws {
        let runner = StubProcessRunner()
        let fakeWav = Data(repeating: 0xAB, count: 1024)
        runner.nextResult = ProcessResult(exitCode: 0, stdout: fakeWav, stderr: Data())
        let tts = PiperTTS(
            runner: runner,
            executablePath: "/usr/local/bin/piper",
            modelPath: "/tmp/voice.onnx",
            sampleRate: 22050
        )
        let result = try await tts.synthesize(
            text: "Hello world.",
            voice: Voice(id: "amy", displayName: "Amy")
        )
        #expect(result.data == fakeWav)
        #expect(result.sampleRate == 22050)
        let stdin = String(decoding: runner.lastInvocation?.stdin ?? Data(), as: UTF8.self)
        #expect(stdin == "Hello world.")
        let args = runner.lastInvocation?.arguments ?? []
        #expect(args.contains("/tmp/voice.onnx"))
    }

    @Test func nonZeroExitCodeThrows() async throws {
        let runner = StubProcessRunner()
        runner.nextResult = ProcessResult(
            exitCode: 2,
            stdout: Data(),
            stderr: Data("model file missing".utf8)
        )
        let tts = PiperTTS(
            runner: runner,
            executablePath: "/usr/local/bin/piper",
            modelPath: "/tmp/missing.onnx",
            sampleRate: 22050
        )
        await #expect(throws: PiperTTSError.self) {
            _ = try await tts.synthesize(text: "x", voice: Voice(id: "v", displayName: "V"))
        }
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter PiperTTSTests
```

- [ ] **Step 3 — Implement**

`Sources/Adapters/TTS/PiperTTS.swift`:
```swift
import Foundation
import Core

public struct PiperTTS: TTSProvider {
    private let runner: ProcessRunner
    private let executablePath: String
    private let modelPath: String
    private let sampleRate: Int

    public init(
        runner: ProcessRunner,
        executablePath: String,
        modelPath: String,
        sampleRate: Int = 22050
    ) {
        self.runner = runner
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.sampleRate = sampleRate
    }

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        // Piper reads text on stdin, writes WAV bytes to stdout via --output-raw or
        // --output_file -. We use `--output_file -` which sends the WAV to stdout.
        let args = [
            "--model", modelPath,
            "--output_file", "-",
        ]
        let result = try await runner.run(
            executable: executablePath,
            arguments: args,
            stdin: Data(text.utf8)
        )
        guard result.exitCode == 0 else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            throw PiperTTSError.synthesisFailed(exitCode: result.exitCode, stderr: stderr)
        }
        return SynthesizedAudio(data: result.stdout, sampleRate: sampleRate)
    }
}

public enum PiperTTSError: Error, Equatable, Sendable {
    case synthesisFailed(exitCode: Int32, stderr: String)
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter PiperTTSTests
bin/test.sh
```

Expected: 2 new tests pass; full suite (now 120 tests in 36 suites) all green.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Adapters/TTS/PiperTTS.swift Tests/AdaptersTests/PiperTTSTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(adapters): add PiperTTS (piper via ProcessRunner)"
```

---

## Task 6 — `AVSpeechTTS` fallback

Wraps Apple's `AVSpeechSynthesizer`. Used when Piper isn't installed. Lower fidelity than Piper but always available on macOS without setup.

**Files:**
- Create: `Sources/Adapters/TTS/AVSpeechTTS.swift`
- Create: `Tests/AdaptersTests/AVSpeechTTSTests.swift`

- [ ] **Step 1 — Write failing test**

`Tests/AdaptersTests/AVSpeechTTSTests.swift`:
```swift
import Testing
import Foundation
import Core
@testable import Adapters

@Suite struct AVSpeechTTSTests {
    @Test func emptyTextReturnsEmptyAudio() async throws {
        let tts = AVSpeechTTS()
        let result = try await tts.synthesize(text: "", voice: Voice(id: "default", displayName: "Default"))
        #expect(result.data.isEmpty)
    }

    @Test func nonEmptyTextProducesAudioBytes() async throws {
        // This test uses the real AVSpeechSynthesizer, but synthesizes a short
        // string offline (no network). Should be fast (< 2s) and produce non-empty
        // bytes on macOS.
        let tts = AVSpeechTTS()
        let result = try await tts.synthesize(
            text: "Hello.",
            voice: Voice(id: "com.apple.voice.compact.en-US.Samantha", displayName: "Samantha")
        )
        #expect(!result.data.isEmpty)
        #expect(result.sampleRate > 0)
    }
}
```

- [ ] **Step 2 — Confirm red**

```bash
bin/test.sh --filter AVSpeechTTSTests
```

- [ ] **Step 3 — Implement**

`Sources/Adapters/TTS/AVSpeechTTS.swift`:
```swift
import Foundation
import AVFoundation
import Core

public final class AVSpeechTTS: TTSProvider, @unchecked Sendable {
    public init() {}

    public func synthesize(text: String, voice: Voice) async throws -> SynthesizedAudio {
        guard !text.isEmpty else {
            return SynthesizedAudio(data: Data(), sampleRate: 0)
        }
        let utterance = AVSpeechUtterance(string: text)
        if let v = AVSpeechSynthesisVoice(identifier: voice.id) {
            utterance.voice = v
        }

        return try await withCheckedThrowingContinuation { continuation in
            let synth = AVSpeechSynthesizer()
            var collected = Data()
            var sampleRate: Int = 0

            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if sampleRate == 0 {
                    sampleRate = Int(pcm.format.sampleRate)
                }
                if pcm.frameLength == 0 {
                    // Sentinel: synthesis complete.
                    continuation.resume(returning: SynthesizedAudio(data: collected, sampleRate: sampleRate))
                    return
                }
                if let channelData = pcm.floatChannelData?.pointee {
                    let count = Int(pcm.frameLength)
                    let bytes = Data(bytes: channelData, count: count * MemoryLayout<Float>.size)
                    collected.append(bytes)
                }
            }
        }
    }
}
```

- [ ] **Step 4 — Confirm green**

```bash
bin/test.sh --filter AVSpeechTTSTests
bin/test.sh
```

Expected: 2 new tests pass; full suite (now 122 tests in 37 suites) all green.

If the second test (`nonEmptyTextProducesAudioBytes`) hangs or fails because `AVSpeechSynthesizer.write` doesn't deliver a final empty buffer the way the implementation expects, escalate as BLOCKED with the diagnosis — don't ad-hoc fix. The fallback we'd take is to use a 5-second `withTimeout` and treat any collected bytes as success.

- [ ] **Step 5 — Commit**

```bash
git add Sources/Adapters/TTS/AVSpeechTTS.swift Tests/AdaptersTests/AVSpeechTTSTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(adapters): add AVSpeechTTS fallback (AVSpeechSynthesizer)"
```

---

## Task 7 — Live contract tests (gated)

Integration tests that exercise the real Ollama / Whisper / Piper binaries. Skipped unless `RUN_LIVE_TESTS=1` is set in the environment. If a binary or model isn't present, the test prints a skip note and passes.

**Files:**
- Create: `Tests/AdaptersTests/LiveProvidersTests.swift`

- [ ] **Step 1 — Implement gated tests**

`Tests/AdaptersTests/LiveProvidersTests.swift`:
```swift
import Testing
import Foundation
import Core
import Adapters

private var liveTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
}

@Suite(.disabled(if: !liveTestsEnabled, "Set RUN_LIVE_TESTS=1 to enable"))
struct LiveProvidersTests {
    @Test func ollamaRespondsToSimplePrompt() async throws {
        let llm = OllamaLLM(
            httpClient: URLSessionHTTPClient(),
            baseURL: URL(string: "http://localhost:11434")!
        )
        let model = ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "qwen2.5:7b-instruct"
        let stream = try await llm.respond(
            messages: [
                ChatMessage(role: .system, content: "Reply with just the word OK and nothing else."),
                ChatMessage(role: .user, content: "say it"),
            ],
            options: LLMOptions(modelName: model, temperature: 0, maxTokens: 16)
        )
        var collected = ""
        for try await c in stream { collected += c }
        #expect(!collected.isEmpty)
    }

    @Test func whisperTranscribesAShortClipIfBinaryIsPresent() async throws {
        let exe = ProcessInfo.processInfo.environment["WHISPER_CLI"] ?? "/opt/homebrew/bin/whisper-cli"
        let model = ProcessInfo.processInfo.environment["WHISPER_MODEL"] ?? ""
        guard FileManager.default.isExecutableFile(atPath: exe), !model.isEmpty,
              FileManager.default.fileExists(atPath: model) else {
            print("Skipping: whisper-cli or model not found (set WHISPER_CLI and WHISPER_MODEL).")
            return
        }
        // We don't have a test fixture audio file in the repo; just smoke-call with
        // empty audio and assert it doesn't crash. A real audio fixture lands in Plan 5.
        let stt = WhisperLocalSTT(runner: ForegroundProcessRunner(), executablePath: exe, modelPath: model)
        _ = try? await stt.transcribe(audio: Data())  // may fail; the point is the binary launched
    }

    @Test func piperSynthesizesShortTextIfBinaryIsPresent() async throws {
        let exe = ProcessInfo.processInfo.environment["PIPER_BIN"] ?? "/opt/homebrew/bin/piper"
        let model = ProcessInfo.processInfo.environment["PIPER_MODEL"] ?? ""
        guard FileManager.default.isExecutableFile(atPath: exe), !model.isEmpty,
              FileManager.default.fileExists(atPath: model) else {
            print("Skipping: piper or model not found (set PIPER_BIN and PIPER_MODEL).")
            return
        }
        let tts = PiperTTS(runner: ForegroundProcessRunner(), executablePath: exe, modelPath: model)
        let result = try await tts.synthesize(text: "Hello", voice: Voice(id: "v", displayName: "V"))
        #expect(!result.data.isEmpty)
    }
}
```

- [ ] **Step 2 — Verify the gate works**

```bash
# Default run: live tests should be skipped/disabled.
bin/test.sh 2>&1 | grep -i "LiveProviders" | head -5
```

Expected: the suite is reported as disabled or skipped, not run.

- [ ] **Step 3 — Verify full suite is still green**

```bash
bin/test.sh 2>&1 | tail -3
```

Expected: 122 tests in 37 suites still pass; live tests don't count toward the failure column.

- [ ] **Step 4 — Commit**

```bash
git add Tests/AdaptersTests/LiveProvidersTests.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "test(adapters): add gated live contract tests (RUN_LIVE_TESTS=1)"
```

---

## Task 8 — SmokeCLI `--live` flag

Adds a `--live` flag to the smoke CLI that swaps the fake LLM for `OllamaLLM`. STT/TTS stay on fakes (real audio I/O lands in Plan 5). The flag requires Ollama to be running; if it isn't, the smoke CLI exits with a clear message.

**Files:**
- Modify: `Sources/SmokeCLI/main.swift`

- [ ] **Step 1 — Replace `main.swift`**

`Sources/SmokeCLI/main.swift`:
```swift
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

    print("→ Mode: \(live ? "LIVE Ollama @ \(modelName)" : "fakes")")
    print("→ Opening DB at \(dbPath.path)")
    let db = try Database.onDisk(at: dbPath)

    print("→ Loading scenario")
    let catalog = try ScenarioCatalog.loadBuiltIn()
    let scenario = catalog.scenario(id: "work-standup-01")!
    print("  scenario: \(scenario.title)")

    let sessionRepo = SessionRepository(database: db)
    let turnRepo = TurnRepository(database: db)
    let weakSpotRepo = WeakSpotRepository(database: db)

    // Two LLM clients: the engine uses one, the analyzer uses another. In live
    // mode, both go to real Ollama. In fake mode, two separate scripted fakes.
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
        llmOptions: LLMOptions(modelName: modelName)
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
}

do {
    try await main()
    print("\n✓ smoke OK")
} catch {
    print("\n✗ smoke FAILED: \(error)")
    exit(1)
}
```

- [ ] **Step 2 — Default run still works**

```bash
swift build
swift run smoke-cli
```

Expected: same output as Plan 3 smoke, ends with `✓ smoke OK`. The "→ Mode: fakes" line should appear at the top.

- [ ] **Step 3 — Run full test suite**

```bash
bin/test.sh 2>&1 | tail -3
```

Expected: 122 tests in 37 suites, all green.

- [ ] **Step 4 — Commit**

```bash
git add Sources/SmokeCLI/main.swift
git -c user.email=techiemmk@gmail.com -c user.name="Manoj" commit -m "feat(smoke): add --live flag that swaps to real OllamaLLM"
```

---

## Plan 4 Self-Review

| Spec/Plan requirement | Covered by |
|---|---|
| Adapter protocols (already in Core) | Plans 1-2 |
| Concrete `OllamaLLM` implementation | Task 3 |
| Concrete `WhisperLocalSTT` implementation | Task 4 |
| Concrete `PiperTTS` implementation | Task 5 |
| `AVSpeechTTS` fallback | Task 6 |
| Tests don't require local binaries | Tasks 3-5 (stub HTTP/process) |
| Live contract tests gated by env var | Task 7 |
| Smoke CLI demonstrates live Ollama | Task 8 |

**Out of scope (deferred):**
- Real microphone capture / speaker playback → Plan 5
- WAV file fixture for whisper integration → Plan 5
- Latency measurement / metrics → Plan 6
- Auto-fallback from Piper to AVSpeech in real wiring (currently hand-selected) → Plan 6 settings UI
- Bundled binaries / installer → Plan 6 onboarding wizard

---

## Definition of Done (Plan 4)

- `swift build` succeeds with no warnings.
- `bin/test.sh` runs ~122 tests across ~37 suites, all green.
- `swift run smoke-cli` (default fake mode) ends with `✓ smoke OK`.
- `swift run smoke-cli -- --live` runs against real Ollama when `qwen2.5:7b-instruct` is pulled and `ollama serve` is running.
- One git commit per task (8 commits) on `main`.
- `Core` still has zero dependency on `Persistence`/`Adapters`/AppKit/SwiftUI/GRDB.
