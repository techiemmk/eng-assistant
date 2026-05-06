# EngAssistant

A native macOS app for practicing **advanced English conversation** with a local AI roleplay partner. Built for the author's personal use; ships fully local — your audio and conversation history never leave your Mac.

**Status:** v1 shipped. SwiftUI app with seven screens, real Ollama-backed conversations, post-session debrief with metrics + weak-spot extraction, on-disk audio persistence.

---

## What it does

You pick a scenario (work standup, conference small talk, dinner with friends, etc.) or describe one yourself. The app plays the AI persona's opening line, you push to talk, the AI responds in character. After you end the session, it analyzes the transcript and gives you a debrief: per-turn metrics, recurring weak spots it noticed across sessions, and suggested drills for next time.

Two modes:
- **Flow** — AI stays in character, never breaks; feedback comes only at the debrief.
- **Coach** — AI subtly inserts inline corrections (`[[coach: try 'I'd rather' instead]]`) that the UI surfaces but the audio strips.

## Quick start

See **[INSTALLATION.md](INSTALLATION.md)** for full setup. Short version:

```bash
brew install ollama
ollama serve &
ollama pull qwen2.5:7b-instruct

# In a new terminal, in the repo root:
scripts/build-app.sh
open EngAssistant.app
```

First launch: right-click the app in Finder → Open (Gatekeeper bypass for unsigned apps). Grant microphone permission when prompted.

## Project structure

```
.
├── README.md                       this file
├── DEVELOPER.md                    how to build, test, extend
├── INSTALLATION.md                 step-by-step user setup
├── Package.swift                   SPM workspace
├── bin/
│   └── test.sh                     test runner (wraps `swift test` for CLT-only)
├── scripts/
│   └── build-app.sh                wraps the binary into EngAssistant.app
├── Sources/
│   ├── Core/                       domain types, protocols, scenario catalog
│   ├── Persistence/                GRDB-backed SQLite repositories
│   ├── Adapters/                   concrete LLM / STT / TTS / Audio implementations
│   ├── Fakes/                      scripted test doubles
│   ├── SmokeCLI/                   CLI smoke harness for the engine
│   └── EngAssistantApp/            SwiftUI app target
├── Tests/
│   └── (CoreTests, PersistenceTests, FakesTests, AdaptersTests, EngAssistantAppTests)
└── docs/
    └── superpowers/
        ├── specs/                  design spec
        └── plans/                  6 implementation plans (v1 milestones)
```

## Architecture at a glance

A layered, protocol-driven design:

- **`Core`** — pure domain (no AppKit/SwiftUI/GRDB/AVFoundation). Models, adapter protocols, persister protocols, the conversation engine, the analyzer.
- **`Adapters`** — concrete provider impls (`OllamaLLM`, `WhisperLocalSTT`, `PiperTTS`, `AVSpeechTTS`, `AVAudioCaptureImpl`, `AVAudioPlaybackImpl`).
- **`Persistence`** — GRDB/SQLite repositories.
- **`Fakes`** — scripted in-memory adapters for tests and the smoke CLI.
- **`EngAssistantApp`** — SwiftUI app, view models, composition root.

Full architectural rationale and trade-offs in [`docs/superpowers/specs/2026-05-04-english-conversation-app-design.md`](docs/superpowers/specs/2026-05-04-english-conversation-app-design.md).

## Implementation history

The project was built in 6 milestone plans, each with detailed TDD task breakdowns:

1. **Foundation & Data Layer** — SPM workspace, schema, repositories
2. **Conversation Engine (fakes)** — adapter protocols, `SessionEngine`, `ChatHistory`, `CoachMarkerParser`
3. **Analysis Engine** — `MetricsAnalyzer`, `WeakSpotExtractor`, `CoachingEngine`
4. **Local Providers** — real Ollama / Whisper / Piper / AVSpeech adapters
5. **Audio I/O** — `AVAudioCaptureImpl`, `AVAudioPlaybackImpl`, WAV codec, VAD
6. **UI v1** — SwiftUI app, all screens, onboarding, retention sweeper

Each plan lives in [`docs/superpowers/plans/`](docs/superpowers/plans/).

## License

Personal-use project; not currently distributed.
