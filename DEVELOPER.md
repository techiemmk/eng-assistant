# Developer Guide

Hands-on reference for building, testing, and extending EngAssistant.

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| macOS | 14+ | `LSMinimumSystemVersion` in `Info.plist` |
| Swift | 6.x | Bundled with Apple Command Line Tools or Xcode |
| Apple CLT or Xcode | Either works | Xcode lets you run `swift test` directly; CLT-only requires `bin/test.sh` (see below) |
| Ollama | Latest | Required at runtime for the real LLM. Install: `brew install ollama` |

Optional, deferred to Plan 7:

- `whisper-cli` (for real STT) — `brew install whisper-cpp`
- `piper` (for real TTS) — see [piper docs](https://github.com/rhasspy/piper)

---

## Building

```bash
swift build                                  # debug build of all targets
swift build --configuration release          # release build
swift run smoke-cli                          # run the engine smoke harness with fakes
swift run smoke-cli -- --live                # smoke harness with real Ollama
scripts/build-app.sh                         # wrap the binary into EngAssistant.app
open EngAssistant.app                        # launch
```

The first build pulls `GRDB.swift` from GitHub (~1-2 min).

---

## Running tests

This repo includes a wrapper script `bin/test.sh` because the project uses **Swift Testing** (not XCTest), which on Apple Command Line Tools needs framework search paths injected. If you have full Xcode installed, plain `swift test` works too.

```bash
bin/test.sh                                  # run everything (fast — ~50ms)
bin/test.sh --filter SessionEngineTests      # filter by suite name
bin/test.sh --filter "specific test name"    # filter by test name
```

### Live integration tests

A few tests require real external binaries (Ollama, whisper-cli, piper) and are gated behind an env var:

```bash
RUN_LIVE_TESTS=1 bin/test.sh --filter LiveProvidersTests
```

These are skipped by default. Without the env var they show as `skipped`, not `failed`.

---

## Module layout

The project is a Swift Package with 6 targets. Dependencies are unidirectional — `Core` depends on nothing external, every other target eventually depends on `Core`.

```
Core ───────────┬────── Persistence
                ├────── Fakes
                ├────── Adapters
                └────── EngAssistantApp ── (Persistence, Adapters)
                                  └────── SmokeCLI ── (Persistence, Fakes, Adapters)
```

| Target | Imports | Responsibility |
|---|---|---|
| `Core` | Foundation only | Domain types, adapter protocols, persister protocols, `SessionEngine`, `SessionAnalyzer`, `ScenarioCatalog`, all pure logic. **No AppKit/SwiftUI/GRDB/AVFoundation.** |
| `Persistence` | `Core` + GRDB | SQLite via GRDB; one repository per table; conformance extensions to Core's persister protocols; `AudioFileStore` for audio paths. |
| `Adapters` | `Core` + Foundation/AVFoundation | `OllamaLLM`, `WhisperLocalSTT`, `PiperTTS`, `AVSpeechTTS`, `AVAudioCaptureImpl`, `AVAudioPlaybackImpl`, `HTTPClient` + `ProcessRunner` ports. |
| `Fakes` | `Core` | Scripted in-memory adapters for tests and the smoke CLI. |
| `SmokeCLI` | `Core` + `Persistence` + `Fakes` + `Adapters` | Hand-runnable engine + analysis demo on a real on-disk DB. |
| `EngAssistantApp` | `Core` + `Persistence` + `Adapters` | SwiftUI app, view models, composition root, screens. |

---

## Test layout

| Test target | Covers | Notable patterns |
|---|---|---|
| `CoreTests` | Models, ScenarioCatalog, engine, analyzer, parser, history | Pure unit tests; uses `Fakes` for adapter substitution |
| `PersistenceTests` | Repositories, migrations, audio file store | Uses `Database.inMemory()` per test for isolation |
| `FakesTests` | The fake adapters themselves | Sanity-check tests |
| `AdaptersTests` | Concrete provider impls | Stub `HTTPClient` and `ProcessRunner` for unit tests; `LiveProvidersTests` for real binaries (gated) |
| `EngAssistantAppTests` | View models + services (`HealthCheck`, `AudioRetentionSweeper`, `AppContainer`) | Pure VM tests; SwiftUI views are not tested |

---

## Common workflows

### Add a new built-in scenario

Edit `Sources/Core/Resources/built-in-scenarios.json`. Run `bin/test.sh --filter ScenarioCatalogTests` to confirm it parses. The Practice screen will pick it up automatically.

### Swap the LLM provider (e.g., add Anthropic Claude)

1. Add a new file under `Sources/Adapters/LLM/` that conforms to `LLMProvider`.
2. Add unit tests with `StubHTTPClient` (see `OllamaLLMTests.swift` as a template).
3. Update `AppContainer.makeLLMProvider()` to return the new provider when configured.
4. Optionally extend the Settings screen to let the user pick.

### Add a new screen

1. Create the view model under `Sources/EngAssistantApp/ViewModels/`. Make it `@MainActor` and `ObservableObject`. Depend only on protocols from `Core`.
2. Write tests in `Tests/EngAssistantAppTests/` using in-memory persister fakes (see `SettingsViewModelTests.swift` for the pattern).
3. Create the SwiftUI view under `Sources/EngAssistantApp/Views/`. Take the view model via `@ObservedObject`.
4. Register the screen in `ContentView`'s `AppPane` enum and switch.

### Run the engine end-to-end without the GUI

```bash
swift run smoke-cli                         # uses fakes
swift run smoke-cli -- --live               # real Ollama (must be running)
```

The smoke writes to `/tmp/eng-assistant-engine-smoke.sqlite` and audio under `~/Library/Application Support/EngAssistantSmoke/`. Persisted audio paths are printed at the end.

---

## Architecture decisions worth knowing

1. **`Core` has zero external dependencies** so it stays testable in isolation and easy to reason about. New adapter protocols live in `Core`; concrete impls live in `Adapters` or `Persistence`.

2. **Audio capture / playback is real** but unit tests don't run real I/O — they exercise pure logic (`WAVCodec`, `VADEndpointer`) and instantiation. Real-mic verification is in `LiveProvidersTests`.

3. **Microphone permission requires the .app bundle** (`Info.plist` + TCC). Bare `swift run` of the app won't get permission. Always launch via `open EngAssistant.app`.

4. **Resource bundle path matters.** `scripts/build-app.sh` copies `EngAssistant_Core.bundle` to the `.app` root (next to `Contents/`), not under `Contents/Resources/`. SPM's `Bundle.module` accessor looks for it there; if you change the script, keep the smoke check.

5. **Swift Testing, not XCTest.** Apple CLT doesn't include XCTest by default but does include the Swift Testing framework. The wrapper script handles the CLT-specific search-path quirk.

6. **All settings persist** via `SettingsRepository` (key/value table). Read at app launch in `AppState.bootstrap()`. Add a new key by adding a case to `AppSettingKey`.

---

## File you might be looking for

| Looking for... | Look in |
|---|---|
| The conversation turn loop | `Sources/Core/Engine/SessionEngine.swift` |
| The post-session analysis pipeline | `Sources/Core/Engine/SessionAnalyzer.swift` |
| The Ollama HTTP client | `Sources/Adapters/LLM/OllamaLLM.swift` |
| The microphone capture | `Sources/Adapters/Audio/AVAudioCaptureImpl.swift` |
| The DB schema / migrations | `Sources/Persistence/Migrations.swift` |
| The app's SwiftUI entry point | `Sources/EngAssistantApp/EngAssistantApp.swift` |
| The screens | `Sources/EngAssistantApp/Views/` |
| The view models | `Sources/EngAssistantApp/ViewModels/` |
| The composition root | `Sources/EngAssistantApp/AppContainer.swift` |
| Built-in scenarios | `Sources/Core/Resources/built-in-scenarios.json` |
| Design spec | `docs/superpowers/specs/2026-05-04-english-conversation-app-design.md` |
| Implementation plans | `docs/superpowers/plans/` |

---

## Known limitations (Plan 7 polish backlog)

- **Live Session uses a placeholder STT** (`ConsoleSTTProvider` in `ContentView.swift`). Real Whisper integration needs the user to install whisper-cli and configure model paths in Settings.
- **Progress Dashboard** screen — deferred.
- **Weak Spots Notebook** with mark-as-resolved UI — deferred.
- **Audio replay buttons** in Debrief — deferred.
- **Custom Scenario authoring UI** — deferred.
- **Session resume** after a crash — the data layer supports it (`SessionPersisting.listActive`), but the UI doesn't expose it yet.
- **`LiveSessionViewModel.runUserTurn`** uses `engine.sessionForTesting()` from production code — label smell, harmless today, plan to clean up.
- **View models rebuild on every navigation switch** in `ContentView` — a Settings page with unsaved edits will lose them on tab change.
- **Pre-existing Sendable warnings** on `Database` and `WeakSpotRepository` — known, deferred.
