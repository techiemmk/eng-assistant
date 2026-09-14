# EngAssistant

A native macOS app for practicing **advanced English conversation** with a local AI roleplay partner. Built for the author's personal use; ships fully local — your audio and conversation history never leave your Mac.

**Status:** v1 shipped, in daily use. SwiftUI app — launch, onboarding, practice,
live session, debrief, sessions history and settings — with real Ollama-backed
conversations, whisper.cpp speech-to-text, cached post-session debriefs carrying
metrics and weak-spot extraction, and on-disk audio you can play back.

**Platform:** macOS 14+ only, and not portable without a rewrite — see
[INSTALLATION.md](INSTALLATION.md).

---

## What it does

You pick a scenario (work standup, patient consultation, conference small talk, dinner with friends, etc.) or describe one yourself. The app plays the AI persona's opening line, you push to talk (the mic stays open until you tap again or pause for ~1.5s), the AI responds in character. After you end the session, it analyzes the transcript and gives you a debrief: per-turn metrics, recurring weak spots it noticed across sessions, and suggested drills for next time.

Scenarios are grouped into five practice domains, which are also the filter
chips on the Practice screen:

- **Homeopathy** (10) — weighted towards case-taking: a first constitutional
  consultation, a guarded patient who answers in four words, one who buries the
  useful detail in a five-minute story, a child whose parent answers for her,
  sensitive symptoms the patient keeps skirting, and someone who has already
  picked his own remedy online. Plus explaining potencies to a sceptic,
  assessing a follow-up response, holding a boundary with a patient who wants to
  stop her prescription, and explaining your approach to a GP.
- **Medical** (5) — taking a patient history, explaining a diagnosis in plain
  English, clinical handover, a difficult conversation with a family member,
  presenting at an MDT meeting.
- **Networking** (2) — conference small talk, meeting a new colleague.
- **Social** (2) — dinner with friends, defending an opinion about a film.
- **Workplace** (2) — the daily engineering standup and a skip-level 1:1 with a
  VP.

The debrief is computed once and cached, so revisiting an old session is
instant and doesn't re-run the model. Each weak spot there has a **Resolve**
button — retiring one stops coach mode targeting it — and every turn with a
recording has a play button, so you can hear your own answers back.

If the app quits mid-conversation, the next launch offers that session back
rather than leaving it stranded.

You can also **continue** a past conversation instead of starting over: the
Sessions list has a Continue button on every row, which reopens that session and
replays its turns back into the model's context, so the persona picks up where
it left off rather than greeting you again. Sessions can be deleted from the same
list — the transcript and its recordings go with them.

Two modes:
- **Flow** — AI stays in character, never breaks; feedback comes only at the debrief.
- **Coach** — AI inserts inline corrections (`[[coach:grammar: try 'I finished' instead of 'I have finish']]`) that the UI surfaces but the audio strips. Corrections are labelled by category, grammar mistakes are always flagged, and the wording you got wrong is underlined in your own transcript bubble. Coach mode is also told your recurring weak spots from past sessions, so it watches for those specifically — the session header shows which ones it's targeting.

## Quick start

**macOS only.** Full step-by-step setup, written for non-technical readers, is
in **[INSTALLATION-macos.md](INSTALLATION-macos.md)**;
[INSTALLATION.md](INSTALLATION.md) is the per-OS index. Short version for the
impatient:

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
├── INSTALLATION.md                 which guide to read for your OS
├── Package.swift                   SPM workspace
├── INSTALLATION-macos.md           the actual install guide
├── INSTALLATION-windows.md         why it can't run there
├── INSTALLATION-linux.md           why it can't run there
├── bin/
│   └── test.sh                     test runner (wraps `swift test` for CLT-only)
├── scripts/
│   ├── build-app.sh                wraps the binary into EngAssistant.app
│   └── make-app-icon.swift         draws Resources/AppIcon.icns
├── Resources/
│   └── AppIcon.icns                generated, committed
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

## Look and feel

The app icon is a speech bubble holding a letter — spoken language, not
messaging — on the same indigo gradient the onboarding hero and launch screen
use. It's generated by [`scripts/make-app-icon.swift`](scripts/make-app-icon.swift)
rather than hand-drawn, so the design is reviewable in code and a colour change
is a one-line edit; the resulting `Resources/AppIcon.icns` is committed, so
building doesn't require running the generator.


Light or dark, switchable in **Settings > Appearance** and applied the moment you
pick it; light is the default. There's deliberately no "follow the system"
option — the app picks one so the look doesn't change under you when macOS flips
at sunset. Every colour is a light/dark pair, and tests hold each variant to a
4.5:1 contrast ratio against its own card surface rather than trusting the eye. The type scale runs noticeably larger than macOS defaults
(17pt body rather than 13pt); `Theme.textScale` in
[`Sources/EngAssistantApp/Theme.swift`](Sources/EngAssistantApp/Theme.swift) is
the one knob if you want it larger or smaller again.

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
