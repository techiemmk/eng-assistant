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

Optional:

- `whisper-cli` (speech-to-text) — `brew install whisper-cpp`, plus a ggml model in
  `~/Library/Application Support/EngAssistant/models/`. Both are auto-detected at
  launch (`STTLocator`); without them the Live Session screen reports that STT is
  unconfigured rather than fabricating a transcript.
- `piper` (alternative TTS) — see [piper docs](https://github.com/rhasspy/piper).
  `AVSpeechTTS` is the default and needs nothing installed.

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

## Runtime wiring worth knowing

**Settings are read through one store.** `AppSettingsStore` holds the *saved*
settings; `AppState.bootstrap()` hydrates it, `ContentView` reads `modelName`
from it for both the session and the debrief analyzers, and `SettingsViewModel`
calls `store.apply(...)` after a successful save so a changed model takes effect
without a relaunch. Nothing outside `AppDefaults` should hardcode a model name.

**A user turn is two calls, not one.** `SessionEngine.beginUserSpeech()` opens
the mic and returns; `finishUserSpeech()` closes it and runs transcribe → LLM →
speak. `runUserTurn()` still exists and does both back-to-back, which is right
for the smoke CLI and tests but would record nothing in a GUI. The live screen
polls `captureHasEndpointed()` every 200 ms so a pause ends the turn on its own
(`AVAudioCaptureImpl` reports its `VADEndpointer` state through
`AudioCapture.hasEndpointed()`; capture devices without VAD keep the protocol
extension's `false` and wait for the second tap).

**Setup failures are typed, not HTTP.** `OllamaLLM` maps 404 to
`OllamaLLMError.modelNotInstalled` and 402 to `.modelRequiresSubscription`;
`WhisperLocalSTT` preflights both its paths. `FriendlyError.message(for:)` is
what the UI renders — add new adapter errors as `LocalizedError` and it picks up
`errorDescription` for free.

**Type scale and palette live only in `Theme`.** Views must not reach for
`.font(.caption)` or `.foregroundStyle(.secondary)`: the first makes text size
untunable, and the second bypasses the light/dark pairs. `Theme.textScale` is
the single knob for overall text size, and `Theme.Size` exposes the point values
separately from the `Font` values because `Font` is opaque —
`ThemeTypeScaleTests` asserts on those numbers.

**Colours are dynamic pairs, and the theme is applied at the app level.** Each
token is an `NSColor(name:dynamicProvider:)` that resolves per appearance at
draw time, which keeps `Theme`'s API static with no environment plumbing.
`AppearancePreference` is deliberately just `.light` and `.dark` — there is no
"follow the system" case, so `nsAppearance` is non-optional and the app always
overrides. A database written before that change can still hold `"system"`;
`AppSettingsStore.reload` treats any unrecognised value as the default (light).
The switch itself goes through `NSApp.appearance`, *not*
`preferredColorScheme` — setting it on the application covers the titlebar and
menus, which sit outside the SwiftUI tree, and it avoids a trap: the `App` body
cannot observe `AppSettingsStore`, because SwiftUI does not republish a nested
`ObservableObject`, so a modifier reading `appState.settings?.appearance` would
silently go stale. `AppSettingsStore` applies the change itself through an
injected `AppearanceApplying` closure (`NSApp` is nil outside a real app
process, so tests substitute a recorder). `ThemePaletteTests` holds every
text colour to 4.5:1 against its own card surface *in both appearances*, which
is what forced the original dark-background accents to be darkened.

**Resuming a session** (`SessionEngine.resume(sessionId:)`) rebuilds
`ChatHistory` from the stored turns instead of creating a session, so the model
gets the earlier conversation back as context. Two turns are deliberately left
out of that replay: turn 0 when it's the AI (the scenario's opening line was
never in history — the model didn't author it, and replaying it teaches it to
re-greet), and any turn marked incomplete (the user half of a turn whose reply
failed, which would leave a dangling user message). An ended session is put back
to `.active` via `SessionPersisting.reactivate`, which also clears `ended_at` so
the duration spans the whole conversation. New turns continue the existing
numbering.

**Scenario collections.** `PracticeViewModel.Collection` is either a domain or a
tag, because the work domain now holds office, clinical and homeopathy
scenarios. Tags that represent a whole track are listed in
`PracticeViewModel.trackTags`, and a chip only appears if the catalog actually
contains that track. The track tags are kept **disjoint** — a scenario carries
at most one — so the chips partition the catalog rather than overlapping;
`HomeopathyScenarioTests.trackTagsDoNotOverlap` enforces that.

**Status labels must not move their own text.** `ActivityLabel` keeps the words
outside its `TimelineView` and animates only three fixed-size dots by opacity.
An earlier version animated the whole row and grew a "•" string from one dot to
three; SwiftUI can't interpolate text, so it crossfaded the label, and the
growing string reflowed everything beside it — the words visibly danced. The
reserved dot width was also a hardcoded 18pt, which three glyphs overflow at
anything above the default font size. `LaunchView` goes further and is entirely
static apart from a standard indeterminate `ProgressView`: a splash screen is
the first impression, and animated wording there reads as restless.

**The launch screen is a deliberate pause.** `AppState.bootstrap` measures its
own elapsed time and sleeps only the remainder of `launchHold` (3s), so a slow
first launch running migrations doesn't pay the hold on top of its own work. A
bootstrap *failure* skips the hold entirely — no reason to make someone wait to
read an error. The hold is injectable so tests don't sit through it.

**Deleting a session** removes audio first, then the database rows. That order
matters: if the audio delete fails the row survives, so the clips are still
reachable to retry, whereas the reverse would orphan files with nothing pointing
at them. `SessionRepository.delete` removes turns explicitly rather than relying
on the schema's `ON DELETE CASCADE`, which only fires when SQLite's
`foreign_keys` pragma is on — one transaction is cheaper than depending on a
connection setting.

**Coach mode's feedback path.** `PersonaBuilder` asks for
`[[coach:<category>: try 'X' instead of 'Y']]` (or `drop 'Y'` for deletions) and
appends the user's `activeWeakSpots` so the model targets recurring mistakes;
`ContentView` supplies those from `AppContainer.activeWeakSpots()`, but only in
coach mode. `CoachMarkerParser` splits each marker into a `Correction` carrying
the category and the quoted `offendingText`, which `LiveSessionView` underlines
inside the *user's* bubble — corrections describe what the user said, so
`refreshTranscript` attaches them to the latest user turn, not the AI reply.
Adding a `WeakSpotCategory` case automatically extends the prompt's category
list and needs a matching colour/icon/label in `Theme`.

**`HealthCheck.localModels` filters cloud entries.** A `:cloud` model (or one
with a `remote_host`) appears in `/api/tags` but needs an Ollama subscription to
answer, so counting it as installed is how a green setup check becomes a 402 on
the first turn.

---

## Known limitations (polish backlog)

- **whisper.cpp isn't bundled** — the user installs it themselves; `STTLocator`
  finds it, and `AppContainer.makeSTTProvider(settings:)` falls back to
  `UnconfiguredSTTProvider` when it's absent.
- **Progress Dashboard** screen — deferred.
- **Medical scenarios sit in the `work` domain**, surfaced by the `medical` tag
  rather than a domain of their own — deliberate, but if the clinical track
  grows much further it probably wants its own `ScenarioDomain` case.
- **Weak Spots Notebook** with mark-as-resolved UI — deferred. `WeakSpotRepository.markResolved` exists and is unused by any screen, so a weak spot can only stop being targeted by the merger aging it out.
- **Audio replay buttons** in Debrief — deferred.
- **Custom Scenario authoring UI** — deferred.
- **Session resume** after a crash — the data layer supports it (`SessionPersisting.listActive`), but the UI doesn't expose it yet.
- **`LiveSessionViewModel`** uses `engine.sessionForTesting()` from production code — label smell, harmless today, plan to clean up.
- **View models rebuild on every navigation switch** in `ContentView` — a Settings page with unsaved edits will lose them on tab change.
- **Pre-existing Sendable warnings** on `Database` and `WeakSpotRepository` — known, deferred.
