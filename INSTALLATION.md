# Installing Jul EngAssistant

## Pick your operating system

| Your computer | Guide | Can you run the app? |
|---|---|---|
| **Mac** (macOS 14 Sonoma or newer) | **[INSTALLATION-macos.md](INSTALLATION-macos.md)** | **Yes** — full step-by-step guide, written for non-technical readers |
| **Windows** | [INSTALLATION-windows.md](INSTALLATION-windows.md) | No — explains why, and what your options are |
| **Linux** | [INSTALLATION-linux.md](INSTALLATION-linux.md) | No — explains why, and what your options are |
| **Mac older than macOS 14** | — | No. Check with  → About This Mac. macOS 14 is the minimum |

---

## Before you spend time on this: it's Mac-only

Jul EngAssistant is a native macOS application and does not run on Windows or
Linux. That is not a missing feature — the interface is built with Apple's
SwiftUI and AppKit, the microphone and voice use Apple's AVFoundation, and the
database layer uses a library that doesn't support other platforms. Porting it
would mean rewriting those layers, not changing a setting.

The Windows and Linux pages above explain this properly, including what a port
would take if you're a developer who wants to attempt one.

Worth knowing if you're on Windows or Linux and disappointed: the two AI
components this app depends on — **Ollama** and **whisper.cpp** — both run
perfectly well on your system. It's only the app wrapped around them that is
Mac-bound.

---

## What you're installing, on a Mac

The app is small; the AI is not. Everything runs on your own machine, and
nothing you say or type is ever uploaded.

- **Ollama** plus a language model (~5 GB) — the conversation partner
- **whisper.cpp** plus a speech model (~150 MB) — so the app can hear you
- **Homebrew** and **Apple Command Line Tools** — to install the above and build
  the app

Budget about 8 GB of disk space and 30 minutes, most of it waiting on downloads.

---

## Where your data lives

All on your Mac, in one folder:

```
~/Library/Application Support/EngAssistant/
```

Conversation history and settings in `eng-assistant.sqlite`, voice recordings
under `audio/`, and the speech model under `models/`. Copy that folder to back
up; delete it to start fresh.

---

## Related documents

- **[README.md](README.md)** — what the app does and how it's built
- **[DEVELOPER.md](DEVELOPER.md)** — building, testing and extending it
