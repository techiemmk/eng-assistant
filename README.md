# EngAssistant

A native macOS app for practicing **advanced English conversation** with a local AI roleplay partner. Built for the author's personal use; ships fully local — your audio and conversation history never leave your Mac.

**Status:** v1 shipped. SwiftUI app with seven screens, real Ollama-backed conversations, whisper.cpp speech-to-text, post-session debrief with metrics + weak-spot extraction, on-disk audio persistence.

---

## What it does

You pick a scenario (work standup, conference small talk, dinner with friends, etc.) or describe one yourself. The app plays the AI persona's opening line, you push to talk (the mic stays open until you tap again or pause for ~1.5s), the AI responds in character. After you end the session, it analyzes the transcript and gives you a debrief: per-turn metrics, recurring weak spots it noticed across sessions, and suggested drills for next time.

Two modes:
- **Flow** — AI stays in character, never breaks; feedback comes only at the debrief.
- **Coach** — AI inserts inline corrections (`[[coach:grammar: try 'I finished' instead of 'I have finish']]`) that the UI surfaces but the audio strips. Corrections are labelled by category, grammar mistakes are always flagged, and the wording you got wrong is underlined in your own transcript bubble. Coach mode is also told your recurring weak spots from past sessions, so it watches for those specifically — the session header shows which ones it's targeting.

## Quick start

See **[INSTALLATION.md](INSTALLATION.md)** for full setup. Short version:

```bash
brew install ollama
ollama serve &
ollama pull qwen2.5:7b-instruct        # a LOCAL model; ":cloud" entries won't work

brew install whisper-cpp               # optional, but needed for the app to hear you
mkdir -p ~/Library/Application\ Support/EngAssistant/models
curl -L -o ~/Library/Application\ Support/EngAssistant/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# In a new terminal, in the repo root:
scripts/build-app.sh
open EngAssistant.app
```

First launch: right-click the app in Finder → Open (Gatekeeper bypass for unsigned apps). Grant microphone permission when prompted. The setup wizard verifies that Ollama has a usable local model — a running server with nothing pulled is the most common cause of a failed first turn.

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
7. **Wiring & diagnostics** — settings-driven model selection, VAD-backed push-to-talk, Whisper wired into the GUI, actionable setup errors

Each plan lives in [`docs/superpowers/plans/`](docs/superpowers/plans/).

## License

Personal-use project; not currently distributed.
