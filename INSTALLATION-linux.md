# Installing Jul EngAssistant on Linux

## The short answer: you can't

**Jul EngAssistant is a Mac-only application.** It cannot be installed on
Linux — no package, no AppImage, no Flatpak, no build flag.

This is not a gap waiting to be filled. About half the app is made of Apple
frameworks that have no Linux equivalent. This page explains why, so you don't
spend an evening trying, and sets out your real options.

If you have access to a Mac, the guide you want is
**[INSTALLATION-macos.md](INSTALLATION-macos.md)**.

---

## Why it can't run on Linux

Linux users often assume the blocker is Swift. It isn't — Swift has run on Linux
for years and is well supported. The blockers are three Apple-only dependencies:

1. **The entire user interface** is SwiftUI and AppKit. Every window, button and
   list in the app is built with them, and neither exists on Linux. There is no
   compatibility layer that would make this build, and 13 of the app target's
   27 files import one of them.
2. **The microphone, the speaker and the voice** are AVFoundation: recording
   you, detecting when you stop talking, playing the reply, and synthesising the
   speech with Apple's system voices. Linux has ALSA/PulseAudio/PipeWire and
   separate speech engines — all different APIs.
3. **The database layer.** History is stored through GRDB, whose own
   documentation states: *"Linux is not currently supported."* So even the
   storage layer would not compile, independent of the UI.

### What *does* work on Linux

Both AI dependencies are fine here, which is the counter-intuitive part:

- **Ollama** has first-class Linux support and is often run on Linux servers.
- **whisper.cpp** builds and runs well on Linux, and typically faster than on a
  Mac if you have a decent GPU.

So the intelligence this app depends on is perfectly at home on Linux. It's the
application shell around it that is Mac-bound.

---

## Your options

### 1. Use a Mac

macOS 14 (Sonoma) or newer. Follow
[INSTALLATION-macos.md](INSTALLATION-macos.md). This is the only route that
works today.

### 2. A macOS virtual machine — not worth it

Apple's licence permits macOS only on Apple hardware, so this project won't
document it. Beyond the licensing question, VM audio passthrough is unreliable,
and microphone input is the one thing this app cannot do without.

### 3. Build a Linux version

Nobody is doing this. If you want to, read on — the codebase is better shaped
for it than most, but it is still a port.

---

## For a developer: what porting would actually involve

The project is layered, and the layers differ sharply in portability. This is
from inspecting the imports, not a guess:

| Layer | Files | Portability |
|---|---|---|
| `Core` | 35 | **Portable.** Foundation only. Conversation engine, persona/prompt building, coach-marker parsing, metrics, weak-spot logic |
| `Fakes` | 10 | **Portable.** Foundation only |
| `Adapters` — `OllamaLLM`, `URLSessionHTTPClient`, `WhisperLocalSTT`, `ForegroundProcessRunner`, `WAVCodec`, `VADEndpointer` | — | **Likely portable.** Foundation and subprocess only. The Ollama HTTP client and whisper.cpp wrapper should need little more than testing |
| `Adapters` — `AVAudioCaptureImpl`, `AVAudioPlaybackImpl`, `AVSpeechTTS` | 3 | **Replace.** AVFoundation |
| `Persistence` | 19 | **Replace.** GRDB is unsupported on Linux |
| `EngAssistantApp` | 27 (13 Apple-only) | **Rewrite.** SwiftUI/AppKit |

The layering helps: every platform-specific piece already sits behind a protocol
declared in `Core` — `AudioCapture`, `AudioPlayback`, `TTSProvider`,
`STTProvider`, `LLMProvider`, and the `SessionPersisting` / `TurnPersisting` /
`WeakSpotPersisting` / `SettingsPersisting` / `DebriefPersisting` family. A port
writes new conformances to those and leaves the domain logic alone.
`DEVELOPER.md` documents those seams.

Concretely, you would need to write:

- **Audio capture** over PipeWire/PulseAudio/ALSA satisfying `AudioCapture`,
  including the `hasEndpointed()` voice-activity signal the push-to-talk
  auto-stop relies on. `VADEndpointer` itself is portable — only the capture
  plumbing is not.
- **Playback** satisfying `AudioPlayback` (it only needs to play a WAV buffer
  and return when finished).
- **Text-to-speech** satisfying `TTSProvider` — Piper is the obvious candidate,
  and there is already an unused `PiperTTS` adapter in the tree to build on.
- **A SQLite layer** behind the `*Persisting` protocols, replacing GRDB. The
  schema is plain SQL in `Sources/Persistence/Migrations.swift`.
- **A user interface.** This is the large one. There is no credible
  cross-platform Swift UI toolkit, so in practice this means GTK bindings, a
  web front end over a local server, or a terminal UI.

A useful first milestone, if you attempt it: `Sources/SmokeCLI` already drives
the whole conversation engine from the command line with fake audio. Getting
that running on Linux — with a replaced persistence layer — would prove the core
is portable before any UI work begins.
