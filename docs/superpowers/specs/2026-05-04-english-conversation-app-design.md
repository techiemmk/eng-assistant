# English Conversation Practice App — Design Spec

**Date:** 2026-05-04
**Author:** Manoj Kumar M
**Status:** Approved for implementation planning
**Target user:** Single user (the author) — personal use on macOS

---

## 1. Goal & Scope

A native macOS desktop app for practicing **advanced English conversation** with a local AI roleplay partner. The user already has solid grammar fundamentals and wants to develop:

- **Fluency under pressure** — speak without long pauses, reduce native-language translation lag.
- **Situational mastery** — confidently handle real scenarios in three domains: professional/work, networking & small talk, and social/casual.

The app is the user's daily/weekly speaking gym: a private place to roleplay scenarios, get coached on recurring weak spots, and track progress over time.

### In scope (v1)
- AI voice roleplay (turn-based, push-to-talk + VAD).
- Both flow mode (no interruption) and coach mode (gentle inline correction), toggleable per session.
- Built-in scenario library + ad-hoc custom scenarios.
- Per-session debrief with metrics, transcript highlights, and weak-spot extraction.
- Long-term progress tracking with a "weak spots notebook" that adaptively primes future sessions.
- Fully local execution — no cloud, no internet required.
- Pluggable provider architecture (STT / LLM / TTS adapters) so cloud APIs can be added later without app rewrites.

### Out of scope (v1)
- Multi-user / accounts / cloud sync.
- Mobile, web, or non-macOS platforms.
- Group conversations, multi-persona scenes.
- Real-time full-duplex audio (turn-based only).
- Pronunciation analysis using formant/phoneme-level acoustic models (filler-word and pace metrics only in v1).
- Cloud LLM/TTS providers (architecture supports them, but v1 ships local only).

### Non-goals
- Replacing a human tutor or language exchange.
- Translation, grammar drilling for absolute beginners.
- Gamification (streaks, badges) — explicitly avoided to keep the app calm and useful.

---

## 2. User Experience Overview

The app opens to **Practice** — the home screen. The user either:

1. Browses the **scenario library** (cards organized by domain: Work, Networking, Social), or
2. Types a **custom scenario** in plain English (e.g., *"I'm meeting my new manager tomorrow, she's friendly but skeptical, we'll discuss my Q2 goals"*).

They pick a **mode** (Flow or Coach) and tap **Start**. The Live Session screen is intentionally minimalist — a persona name, a microphone button, the live transcript, and a replay-last button. After ending the session, they see a **Debrief**: highlights, metrics, and any newly detected weak spots.

Other screens — Sessions History, Progress Dashboard, Weak Spots Notebook, Settings — are accessed from a sidebar.

---

## 3. Architecture

A native macOS SwiftUI app organized as a **layered, protocol-driven** monolith. The codebase is split into Swift Package Manager modules so the domain layer can be unit-tested without UI, audio, or model dependencies.

```
┌─────────────────────────────────────────────────────────┐
│  UI Layer  (SwiftUI views, view models)                 │
│  Practice, Live Session, Debrief, Sessions, Progress,   │
│  Weak Spots, Settings                                   │
├─────────────────────────────────────────────────────────┤
│  Domain Layer  (Core)                                   │
│  SessionEngine, PersonaBuilder, MetricsAnalyzer,        │
│  WeakSpotExtractor, CoachingEngine, ScenarioCatalog     │
├─────────────────────────────────────────────────────────┤
│  Adapter Layer  (protocols + concrete impls)            │
│  STTProvider     → WhisperLocalSTT                      │
│  LLMProvider     → OllamaLLM                            │
│  TTSProvider     → PiperTTS / AVSpeechTTS (fallback)    │
│  AudioCapture, AudioPlayback                            │
├─────────────────────────────────────────────────────────┤
│  Persistence  (GRDB / SQLite)                           │
│  Sessions, Turns, WeakSpots, Scenarios, Metrics, etc.   │
├─────────────────────────────────────────────────────────┤
│  External processes (user's machine):                   │
│  Ollama (localhost:11434), whisper.cpp, Piper TTS       │
└─────────────────────────────────────────────────────────┘
```

### Key architectural decisions

- **Turn-based pipeline.** User speaks → STT → LLM → TTS → playback. No full-duplex streaming in v1.
- **Each layer depends only downward.** UI calls `SessionEngine`; never touches Ollama or audio APIs directly.
- **All providers behind protocols.** `STTProvider`, `LLMProvider`, `TTSProvider` — concrete implementations are swappable without touching domain logic. This is what enables future cloud upgrades.
- **Ollama sidecar for v1.** App talks to a locally-running `ollama serve` process via HTTP. Default model: `qwen2.5:7b-instruct`. User can swap models via Settings.
- **Single window, sidebar navigation.** No separate menubar widget in v1.
- **Swift Package Manager workspace.** Modules: `App`, `Core` (domain + protocols), `Adapters` (concrete providers), `Persistence`. The `Core` module has no dependency on AppKit/SwiftUI.
- **Concurrency:** Swift Structured Concurrency throughout. `SessionEngine` is an `actor`; LLM token streams use `AsyncStream`.

### Tech stack summary

| Concern | Choice |
|---|---|
| Language / UI | Swift / SwiftUI (macOS 14+) |
| LLM runtime | Ollama (HTTP localhost:11434), default `qwen2.5:7b-instruct` |
| STT | whisper.cpp via Swift bridge, default `whisper-small.en` |
| TTS | Piper (preferred) with `AVSpeechSynthesizer` as zero-config fallback |
| DB | SQLite via GRDB (embedded; no install required) |
| Audio | AVFoundation (`AVAudioEngine`, `AVAudioPlayer`) |
| Logging | OSLog |
| Testing | XCTest, swift-snapshot-testing |

---

## 4. Components

### 4.1 Adapter Layer

| Component | Responsibility | v1 Implementation |
|---|---|---|
| `STTProvider` | `transcribe(audio: Data) async throws -> Transcript` | `WhisperLocalSTT` — wraps whisper.cpp via Swift bridge |
| `LLMProvider` | `respond(messages: [ChatMessage], opts: LLMOptions) async throws -> AsyncStream<String>` | `OllamaLLM` — HTTP client to localhost:11434 |
| `TTSProvider` | `synthesize(text: String, voice: Voice) async throws -> AudioBuffer` | `PiperTTS` (preferred), `AVSpeechTTS` fallback |
| `AudioCapture` | Start/stop mic, emit raw PCM, VAD endpointing | `AVAudioEngine` + heuristic VAD |
| `AudioPlayback` | Play synthesized AI replies, pause/replay-last | `AVAudioPlayer` |

### 4.2 Domain Layer

| Component | Responsibility |
|---|---|
| `SessionEngine` | Drives the turn loop. Holds session state, builds the LLM prompt (persona + truncated history + mode flags), coordinates STT → LLM → TTS, persists each turn. Emits state changes for the UI. Implemented as an actor. |
| `PersonaBuilder` | Composes the system prompt from a scenario: persona description, conversational style, difficulty knobs (pace, pushback level), language register, mode-specific instructions, and (in coach mode) the user's active weak spots. |
| `MetricsAnalyzer` | After each session: computes WPM, pause ratio, filler density (regex), unique-word ratio, idiom hits (lookup), grammar issues (LLM-as-judge with strict JSON output). Persists to `turns.metrics_json` and `metrics_daily`. |
| `WeakSpotExtractor` | Runs an LLM pass over the session transcript: identifies recurring patterns (not one-offs), normalizes them, tags by category. Deduplicates against existing `weak_spots` rows by pattern similarity. |
| `CoachingEngine` | Produces the post-session debrief: 1-line summary, transcript highlights (filler words, slips, suggested upgrades), new vs recurring weak spots, suggested drills for next session. |
| `ScenarioCatalog` | Loads built-in scenarios from a bundled JSON file, merges with user-created scenarios from DB. Search/filter by domain, tag, difficulty. |

### 4.3 UI Layer (SwiftUI screens)

| Screen | Purpose |
|---|---|
| **First-run Onboarding** | One-time guided wizard: checks Ollama is installed and running, pulls the default LLM model with progress bar, downloads the Whisper model file, requests microphone permission, lets the user pick a default voice. ~90 seconds happy path. |
| **Practice (home)** | Library of scenario cards + "Custom Scenario" free-text box. Mode toggle (Flow / Coach). Banner area for setup issues (Ollama not running, etc.). |
| **Live Session** | Distraction-free. Persona name + 1-line context, mic button (push-to-talk + VAD), live transcript, replay-last. |
| **Debrief** | 1-line summary, transcript with inline highlights, key metrics card, "new weak spots" + "recurring weak spots" sections. |
| **Sessions History** | Chronological list, search, replay any session (audio + transcript). |
| **Progress Dashboard** | Trend charts on fluency, vocab range, grammar slips/min, filler density. 30-day view. Sessions/week. |
| **Weak Spots Notebook** | List of active patterns sorted by frequency. Each: pattern, category, examples, "suggest drill" button, "mark resolved" toggle. |
| **Settings** | Model picker (lists installed Ollama models + "Pull new…"), STT/TTS model & voice pickers, audio retention policy, export/import data, default mode, VAD sensitivity. |

---

## 5. Data Model & Storage

### Storage layout

All data lives under the macOS standard app-data location:

```
~/Library/Application Support/EngAssistant/
├── eng-assistant.sqlite        ← primary DB
├── audio/
│   └── <session-uuid>/
│       ├── user-turn-001.wav
│       └── ai-turn-001.wav
├── transcripts/                ← human-readable mirror, .md per session
│   └── 2026-05-04-meeting-prep.md
├── models/                     ← Whisper + Piper model files
└── logs/
```

### SQLite schema

| Table | Columns (high level) |
|---|---|
| `sessions` | id, scenario_id, started_at, ended_at, mode (`flow`/`coach`), summary, persona_snapshot, status |
| `turns` | id, session_id, turn_index, speaker (`user`/`ai`), text, audio_path, started_at, duration_ms, metrics_json, is_complete |
| `scenarios` | id, source (`builtin`/`custom`), title, persona, opening_line, difficulty, tags, is_user_created, notes |
| `weak_spots` | id, pattern, category (`grammar`/`vocab`/`filler`/`fluency`), first_seen, last_seen, occurrence_count, status (`active`/`resolved`), example_turn_ids |
| `metrics_daily` | date, total_minutes, sessions_count, avg_fluency, avg_vocab_range, avg_filler_density, avg_grammar_slips_per_min |
| `settings` | key, value |

### Data properties

- **Fully local, no cloud sync.** No data leaves the device in v1.
- **Audio retention is configurable.** Default: keep raw user audio for 30 days then purge; transcripts kept forever.
- **Conversation context window:** last ~12 turns or ~3000 tokens, whichever first; older turns summarized into a rolling LLM-generated summary kept in the system message.
- **Cross-session memory** lives in the scenario record (`notes` field) plus the active weak-spots set.
- **Audio is referenced from `turns.audio_path`,** not stored as a blob in the DB.
- **All derived data (metrics, weak spots, debrief) is re-runnable** from the stored transcripts. Future model upgrades can re-analyze old sessions.
- **Transcripts also written as Markdown files** for easy hand-inspection without DB tools.

---

## 6. Data Flow

### Flow A — Single Conversational Turn (the hot loop)

1. User taps mic (or VAD auto-starts).
2. `AudioCapture` records PCM until silence threshold (1.5s default) or user releases push-to-talk.
3. Raw audio is written to `audio/<session-uuid>/user-turn-NNN.wav` **before** STT runs (so speech is never lost).
4. `STTProvider` (Whisper) returns the transcript.
5. `SessionEngine` persists the user turn.
6. `SessionEngine` builds the prompt: system persona + truncated history + mode flags (in coach mode, includes "watch for these recurring user mistakes: …" with active weak spots).
7. `LLMProvider` (Ollama) streams reply tokens. UI renders text live.
8. Once complete, `SessionEngine` parses out `[[coach: …]]` markers (if any), persists the AI turn, and hands the persona-only text to `TTSProvider`.
9. `AudioPlayback` plays the synthesized reply.
10. Loop.

**Coach mode** is a prompt-level switch, not a separate code path. The LLM is instructed to wrap inline corrections in `[[coach: …]]` markers; the UI surfaces them as structured corrections, and TTS skips them so the persona stays in character audibly.

### Flow B — End-of-Session Analysis

1. User clicks "End Session." `SessionEngine` finalizes the session row.
2. **In parallel:**
   - `MetricsAnalyzer` runs (heuristics + one LLM-as-judge pass for grammar). Writes `turns.metrics_json` and rolls up into `metrics_daily`.
   - `WeakSpotExtractor` runs an LLM pass over the transcript to identify recurring patterns. Dedups against existing `weak_spots`; upserts.
3. `CoachingEngine` produces the debrief (summary, highlights, drill suggestions).
4. UI shows the Debrief screen.

**Properties:** runs locally off the UI thread (~5-15s on a MacBook Air), each pass is independently try/catch'd (failure of one doesn't block the others), and all of it is idempotent and re-runnable.

### Flow C — Session Startup (with weak-spot priming)

1. User picks a scenario (library or custom).
2. `ScenarioCatalog` loads or constructs the scenario record.
3. `WeakSpotsQuery` fetches the user's top N active weak spots (default: 5 most frequent).
4. `PersonaBuilder` composes the system prompt: persona + mode flags + weak-spots block + difficulty knobs.
5. `SessionEngine` creates the session row, plays the opening line via TTS, and begins Flow A.

**Cold start:** first-ever session has no weak spots; PersonaBuilder simply omits that section.

---

## 7. Error Handling & Resilience

The principle: **fail visibly and recoverably; never silently degrade fluency practice.**

| Failure | Strategy |
|---|---|
| Ollama not running | Pre-flight ping on app launch; banner with "Launch Ollama" button (spawns `ollama serve` via `Process`). Block "Start Session" with inline message until reachable. |
| Default model not pulled | First-run wizard offers to pull `qwen2.5:7b-instruct` with a progress bar. Settings has a "Pull new model…" flow. |
| Mic permission denied | Pre-flight check before session starts. If denied: explanation screen + deeplink to System Settings. |
| Whisper model file missing/corrupt | Verify checksum on launch; prompt to re-download if missing. |
| STT empty / low-confidence | Inline "I didn't catch that — try again?" message. Don't push empty turns to LLM. |
| LLM timeout / Ollama crash mid-turn | 30s timeout. Mark partial AI turn `incomplete`. Show "Reply failed — retry?" inline. Session stays alive. |
| Malformed coach markers | Tolerant parser: malformed markers stripped from rendered text and logged; turn doesn't crash. |
| TTS failure (Piper crashes / model missing) | Auto-fallback to `AVSpeechSynthesizer`. Visible banner: "TTS fell back to system voice." |
| Disk full | Audio written to tmp first, then moved. On failure: drop audio for that turn; preserve transcript; show one warning. |
| App crash mid-session | Per-turn atomic commits. On next launch, detect orphaned sessions → "Resume" or "Discard." |
| DB schema migration failure | Versioned GRDB migrations; on failure show recovery screen with "Backup & reset DB" option. |
| End-of-session analysis fails | Each analysis pass independently try/catch'd. Partial debriefs allowed. "Re-run analysis" button on Debrief. |
| VAD too aggressive/lax | Sensitivity exposed in Settings. Push-to-talk always available. |
| Long idle mid-session | App releases TTS/STT resources after 5min idle; resumes on interaction. |

### Cross-cutting principles

- **Never lose user speech.** Audio file is written before STT runs.
- **Surface errors at the right altitude.** Setup issues → Practice screen banner; per-turn failures → inline in Live Session; analysis failures → Debrief screen.
- **No silent fallbacks.** Visible banner whenever a fallback engages.
- **No automatic LLM retries.** A failed local LLM generation usually produces another bad reply; the user explicitly retries.
- **First-run onboarding wizard** handles Ollama, default model, mic permission, and Whisper model in one guided 90-second flow.

---

## 8. Testing Strategy

### Coverage by layer

| Layer | What we test | How |
|---|---|---|
| Domain (Core) | `SessionEngine`, `PersonaBuilder`, `MetricsAnalyzer` (heuristic part), `WeakSpotExtractor` dedup, prompt assembly, history truncation, marker parsing | XCTest with fake adapters conforming to provider protocols |
| Persistence | Migrations, CRUD, weak-spot dedup queries, retention sweeper | XCTest against in-memory SQLite |
| Adapters | Ollama HTTP client, Whisper bridge, Piper invocation, marker parser | Contract tests against real Ollama (gated behind `RUN_LIVE_TESTS=1`); HTTP-level tests with stub server for error paths |
| UI | View-model unit tests, snapshot tests for key screens | XCTest + swift-snapshot-testing |
| End-to-end | Scripted session smoke test using fixture audio replayed through `MockAudioCapture` | XCUITest, opt-in |

### Test fixtures

- `FakeLLMProvider`, `FakeSTTProvider`, `FixtureAudioCapture` — scripted, configurable per test.
- Sample transcripts library — `.json` files representing different speaker profiles (filler-heavy, fluent, grammar-prone) for testing analysis without invoking the LLM.
- Sample sessions — full pre-recorded sessions for testing Debrief flow and metrics rollup.

### Critical scenarios (must pass before v1 ship)

1. Turn loop happy path (fakes for STT/LLM/TTS).
2. History truncation at threshold.
3. Coach-mode marker parsing — markers extracted, TTS payload clean.
4. Weak-spot dedup — repeated extraction increments `occurrence_count`, no dupes.
5. Resume interrupted session.
6. Ollama unreachable on startup → banner + Start blocked.
7. Mic permission denied → pre-flight blocks session.
8. Re-run analysis on old session — idempotent, results overwrite cleanly.
9. Schema migration v1 → v2 — data preserved.
10. Audio retention sweeper — old files deleted, transcripts kept.

### Intentionally untested

- LLM output quality (test structure, not content; quality is verified by user in-app).
- TTS audio fidelity (verified that synthesis was invoked, not waveform).
- Mic latency end-to-end on real hardware (manual smoke check per release).

### Tooling

- `swift test` for Swift Package modules; `xcodebuild test` for the App target.
- Coverage targets: Domain ≥80%, Adapter ≥60%, UI ≥40%.
- Default test run requires no Ollama, no models, no mic — pure fakes.
- TDD-first for `Core`; adapter implementations written against protocols last.

### Manual verification checklist (per release)

- 5-min real flow-mode session → debrief reasonable.
- 5-min real coach-mode session → corrections visually distinct, audio clean.
- Pull new model from Settings → selectable, generates a reply.
- Force-quit mid-session → resume works.
- Toggle mic permission off → app handles cleanly.

---

## 9. Open Questions / Future Work

These are explicitly deferred from v1 but the architecture supports them:

- **Cloud LLM/voice providers.** Adapter protocols are designed for this. Add `ClaudeLLM`, `OpenAIRealtime`, `ElevenLabsTTS` concrete implementations and a Settings switcher.
- **Phoneme-level pronunciation analysis.** Would require integrating a forced-aligner like `gentle` or a dedicated acoustic model.
- **Custom voice cloning.** Piper supports it; needs UI + onboarding.
- **Multi-persona scenarios.** Architecture allows it (LLM can play multiple roles), but UI and turn-management need redesign.
- **Cross-device sync.** Out of scope; design favors local-first. Could be added as opt-in via iCloud Drive on the app folder, but not before v2.
- **Scenario-sharing** between users. N/A while it's a personal app; would need import/export beyond just JSON dump.
- **Real-time streaming pipeline.** v1 is turn-based; OpenAI Realtime-style full-duplex would require pipeline changes but no architectural rewrite.

---

## 10. Definition of Done (v1)

- All five sections (Architecture, Components, Data Flow, Error Handling, Testing) implemented as described.
- All "Critical scenarios" tests pass.
- Manual verification checklist passes on the author's MacBook.
- App can be built into a `.app` bundle and installed to `/Applications/`.
- First-run onboarding wizard successfully guides a fresh install through Ollama setup, default model pull, Whisper model download, and mic permission.
- At least 10 built-in scenarios per domain (Work, Networking, Social) — 30 total — bundled with the app.
- Documentation: a short README in the repo root explaining how to build, run, and what dependencies need to be installed (Ollama).
