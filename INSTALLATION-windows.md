# Installing Jul EngAssistant on Windows

## The short answer: you can't, and no workaround will change that

**Jul EngAssistant is a Mac-only application.** It cannot be installed on
Windows. There is no Windows version, no installer, and no setting that makes it
work.

This isn't an oversight or something waiting to be finished — the app is built
out of parts that exist only on macOS. This page explains why, so you're not
left hunting for a download that doesn't exist, and tells you what your actual
options are.

If you have access to a Mac, the guide you want is
**[INSTALLATION-macos.md](INSTALLATION-macos.md)**.

---

## Why it can't run on Windows

Three separate pieces of the app are Apple-only:

1. **Everything you see.** The buttons, the cards, the transcript, the settings
   screen — all of it is written with SwiftUI and AppKit, Apple's tools for
   building Mac windows. There is no version of those for Windows. This is not
   a small part of the app; it is most of what makes it an app rather than a
   script.
2. **The microphone and the voice.** Recording you, detecting when you've
   stopped speaking, and speaking the AI's replies aloud all use AVFoundation
   and Apple's built-in speech voices. Windows has its own, entirely different,
   equivalents.
3. **The database.** The conversation history is stored using a library
   (GRDB) whose own documentation states plainly that non-Apple platforms are
   not supported.

Swift, the programming language, *does* run on Windows. That's the part people
usually assume is the obstacle, and it isn't. The obstacle is that roughly half
of this particular app is Apple frameworks with no Windows counterpart.

### What the AI parts can do

Worth knowing, because it's the opposite of what you'd expect: **the two AI
dependencies run on Windows perfectly well.** Ollama has a Windows installer,
and whisper.cpp builds on Windows. They are not the problem. It's the app
wrapped around them that is Mac-only.

---

## Your options

### 1. Use a Mac — the only route that works today

Any Mac running macOS 14 (Sonoma) or newer. A borrowed Mac, a work Mac, or a
rented cloud Mac (MacStadium, Scaleway and AWS all rent them by the hour) will
all run it. Follow [INSTALLATION-macos.md](INSTALLATION-macos.md).

Be aware that a *rented* Mac has no microphone, so speaking practice won't work
on one — that route only makes sense for looking at the app, not using it.

### 2. Running macOS on your PC — not a real option

You will find guides online for installing macOS on non-Apple hardware. Two
reasons to skip it: Apple's software licence only permits macOS on Apple
hardware, so it isn't something this project will help with; and even when such
a setup boots, microphone input and audio output are usually the first things
that don't work — which is the entire point of this app.

### 3. Wait for, or build, a Windows version

Nobody is working on one. If you're a developer and want to, the next section is
an honest scope.

---

## For a developer: what porting would actually involve

This is a rewrite of the outer layers, not a recompile. The project is split
into layers, and they differ sharply in how portable they are:

| Layer | Portability | Why |
|---|---|---|
| `Core` | **Portable** | Imports only Foundation. The conversation engine, prompt building, coach-marker parsing, metrics and weak-spot logic all live here |
| `Fakes` | **Portable** | Foundation only |
| `Adapters` — Ollama, HTTP, whisper, WAV codec | **Mostly portable** | Foundation and subprocesses. The Ollama client and the whisper.cpp wrapper would need little change |
| `Adapters` — audio capture, playback, TTS | **Needs replacing** | AVFoundation. Three files: `AVAudioCaptureImpl`, `AVAudioPlaybackImpl`, `AVSpeechTTS` |
| `Persistence` | **Needs replacing** | GRDB doesn't support non-Apple platforms. Would need a different SQLite wrapper |
| `EngAssistantApp` | **Needs rewriting** | 13 of 27 files import SwiftUI or AppKit |

The encouraging part is that the layering already isolates this. Every
replaceable piece sits behind a protocol in `Core` — `AudioCapture`,
`AudioPlayback`, `TTSProvider`, `STTProvider`, `LLMProvider`, and the
`*Persisting` family. A port means writing new conformances to those protocols
plus a new UI, without touching the domain logic. See `DEVELOPER.md` for how
those seams work.

What you would need to supply:

- A UI. There is no cross-platform Swift UI toolkit worth relying on; realistically
  this means a different language for the front end, talking to the Swift core,
  or rewriting the interface entirely.
- Microphone capture with voice-activity detection, to satisfy `AudioCapture`.
- Audio playback, to satisfy `AudioPlayback`.
- A text-to-speech voice, to satisfy `TTSProvider`. Windows has SAPI; quality
  varies.
- A SQLite layer to replace GRDB behind the `*Persisting` protocols.

That is weeks of work, not an afternoon. It is a genuine port.
