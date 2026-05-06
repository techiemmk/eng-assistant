# Installation Guide

End-to-end setup for running EngAssistant on a fresh macOS machine. Should take 10-20 minutes depending on your network speed (the LLM model is 4-5 GB).

---

## What you'll need

- A Mac running macOS 14 (Sonoma) or newer
- ~10 GB free disk space (mostly the local LLM model)
- An internet connection (only for the one-time download of Ollama and the model — the app itself runs fully offline once set up)
- Apple Command Line Tools or Xcode installed (for building the app)
- [Homebrew](https://brew.sh) installed (recommended; can also install Ollama manually)

---

## Step 1: Install Apple Command Line Tools

If you have Xcode installed, skip this step. Otherwise:

```bash
xcode-select --install
```

A system dialog will appear; click Install. This is a one-time download (~1 GB).

Verify:

```bash
swift --version
```

You should see `Apple Swift version 6.x` or newer.

---

## Step 2: Install and start Ollama

Ollama is the local LLM runtime. EngAssistant talks to it over HTTP at `localhost:11434`.

```bash
brew install ollama
```

Then start the Ollama server in a terminal window (leave it running):

```bash
ollama serve
```

You should see something like `Listening on 127.0.0.1:11434`.

---

## Step 3: Pull a language model

In a **new** terminal (keep `ollama serve` running):

```bash
ollama pull qwen2.5:7b-instruct
```

This downloads ~4.5 GB and takes a few minutes. Other models will work too — `llama3.2`, `mistral`, etc. — but EngAssistant defaults to `qwen2.5:7b-instruct` (good quality, fits comfortably in 8 GB of RAM).

If you want a different default, edit it in Settings after launching the app.

Verify the model is installed:

```bash
ollama list
```

You should see `qwen2.5:7b-instruct` in the output.

---

## Step 4: Build EngAssistant

Clone or download this repo, then in the repo root:

```bash
scripts/build-app.sh
```

This produces `EngAssistant.app` in the repo root. The first build takes a couple of minutes (Swift compiles GRDB and all targets); subsequent builds are seconds.

If the build fails with `command not found: swift`, return to Step 1 and confirm Apple CLT is installed.

---

## Step 5: First launch

Because the app isn't code-signed, macOS Gatekeeper will block the first launch. **Right-click** `EngAssistant.app` in Finder, choose **Open**, and confirm in the dialog. After this once-only step, you can launch it normally.

```bash
open EngAssistant.app
```

---

## Step 6: Onboarding

The first time the app opens, an onboarding wizard runs:

1. **Ollama running** — should be green if `ollama serve` is running. If red, restart Ollama (Step 2).
2. **Microphone permission** — macOS will pop up a permission dialog. Click "OK". (You can later change this in System Settings → Privacy & Security → Microphone.)

When both are green, click **Continue**. The wizard will not run again on subsequent launches (your choice is persisted).

---

## Step 7: Use it

You're at the Practice screen.

1. Click a scenario card (e.g. "Daily Engineering Standup")
2. Pick **Flow** (no corrections during conversation) or **Coach** (gentle inline corrections)
3. Click **Start Session**
4. The AI plays its opening line through your speakers. Click **Push to talk** when you want to respond. *(Plan-7 note: actual speech-to-text isn't wired into the GUI yet — see "Known limitations" below; for now the app uses a placeholder transcript.)*
5. Click **End Session** when you're done
6. The Debrief screen runs analysis: per-turn metrics, new vs recurring weak spots, suggested drills

The **Sessions** sidebar shows all your past sessions. Click any to revisit its debrief.

The **Settings** sidebar lets you change the LLM model, default mode, and audio retention period.

---

## Where data is stored

Everything stays on your Mac under:

```
~/Library/Application Support/EngAssistant/
├── eng-assistant.sqlite        SQLite DB (sessions, turns, weak spots, settings)
├── audio/
│   └── <session-uuid>/
│       ├── user-turn-001.wav
│       └── ai-turn-002.wav
└── ...
```

To back up, just copy that directory. To start fresh, delete it.

---

## Known limitations in this v1 release

These are tracked for a Plan-7 polish release:

- **Speech-to-text in the GUI is a placeholder.** The infrastructure (`WhisperLocalSTT`) is implemented and tested, but it's not yet selected from Settings. For now the Live Session screen records your audio (and saves the .wav file to disk), but the on-screen transcript shows `[transcription pending whisper.cpp setup]`. The conversation still proceeds; the AI just doesn't get your actual words. Coming soon.
- **No Progress Dashboard** with metric trend charts.
- **Weak Spots Notebook** UI is minimal — patterns appear in the debrief but there's no separate browseable notebook with mark-as-resolved.
- **No audio replay buttons** in the debrief — the .wav files are saved, but the UI doesn't yet play them back.
- **No custom-scenario authoring** — only the bundled six scenarios so far.

---

## Troubleshooting

### "EngAssistant couldn't start: ScenarioCatalogError.bundledResourceMissing"

The app's resource bundle didn't get copied to the right place. Re-run `scripts/build-app.sh` and confirm there's an `EngAssistant_Core.bundle` directory inside `EngAssistant.app/` (next to `Contents/`, not inside it). If it's still missing, file an issue.

### App launches but sits on "Initializing..." forever

Likely a database-open or resource-load failure that's not surfacing. Check Console.app (filter for "engassistant"). If the resource bundle is missing, see the error above.

### Onboarding shows "Ollama isn't running"

Open a terminal and run `ollama serve`. The check re-runs every time you click "Run checks" on the wizard.

### Onboarding shows "Microphone access denied"

Open System Settings → Privacy & Security → Microphone, find EngAssistant in the list, and toggle it on. Then quit and relaunch the app. If EngAssistant isn't in the list, microphone access has never been requested — make sure you're launching the *bundled* `EngAssistant.app`, not running `swift run` directly.

### "ollama pull" fails with disk space errors

The `qwen2.5:7b-instruct` model is ~4.5 GB. If you're tight on space, try a smaller model: `ollama pull qwen2.5:3b-instruct` (~2 GB) and update the model name in EngAssistant Settings.

### The conversation feels slow / choppy

The first AI reply after starting a session warms up Ollama (a few seconds). Subsequent turns are faster. If it's consistently slow, you may be running a model too big for your Mac's RAM — try `qwen2.5:3b-instruct` or `phi3:mini`.

### I want to uninstall

```bash
rm -rf EngAssistant.app
rm -rf ~/Library/Application\ Support/EngAssistant
brew uninstall ollama   # optional, if you don't use Ollama for anything else
```
