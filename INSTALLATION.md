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

**Cloud models don't count.** An entry tagged `:cloud` (e.g. `minimax-m3:cloud`) is
hosted by ollama.com, not by your Mac — running one needs an Ollama subscription,
and without credits EngAssistant will report that the model can't be used. You need
at least one genuinely local model. The app's setup wizard checks for this
explicitly and ignores cloud entries.

---

## Step 4 (optional): Install speech-to-text

Without this, EngAssistant can still hold a conversation but can't hear your
words — the Live Session screen will tell you speech-to-text isn't set up.

```bash
brew install whisper-cpp
```

Then download a ggml model into the app's models directory:

```bash
mkdir -p ~/Library/Application\ Support/EngAssistant/models
curl -L -o ~/Library/Application\ Support/EngAssistant/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

`ggml-base.en.bin` is ~150 MB and good enough for practice; `ggml-small.en.bin`
(~500 MB) is more accurate. The app auto-detects both the binary and the model on
launch — if it doesn't, open **Settings > Speech-to-text** and click **Auto-detect**,
or type the paths in by hand.

---

## Step 5: Build EngAssistant

Clone or download this repo, then in the repo root:

```bash
scripts/build-app.sh
```

This produces `EngAssistant.app` in the repo root. The first build takes a couple of minutes (Swift compiles GRDB and all targets); subsequent builds are seconds.

If the build fails with `command not found: swift`, return to Step 1 and confirm Apple CLT is installed.

---

## Step 6: First launch

Because the app isn't code-signed, macOS Gatekeeper will block the first launch. **Right-click** `EngAssistant.app` in Finder, choose **Open**, and confirm in the dialog. After this once-only step, you can launch it normally.

```bash
open EngAssistant.app
```

---

## Step 7: Onboarding

The first time the app opens, an onboarding wizard runs:

1. **Ollama running** — should be green if `ollama serve` is running. If red, restart Ollama (Step 2).
2. **Language model installed** — green when Ollama has the configured model locally. If red, it tells you the exact `ollama pull` command, and lists any other local models you could select in Settings instead.
3. **Microphone permission** — macOS will pop up a permission dialog. Click "OK". (You can later change this in System Settings → Privacy & Security → Microphone.)
4. **Speech-to-text (optional)** — green when whisper-cli and a ggml model are both found (Step 4). This one is advisory: you can click **Get started** with it red and set it up later in Settings.

When the first three are green, click **Get started**. The wizard will not run again on subsequent launches (your choice is persisted).

---

## Step 8: Use it

You're at the Practice screen.

1. Click a scenario card (e.g. "Daily Engineering Standup", or one of the
   **Medical** track cards if you're a clinician — patient consultation,
   explaining a diagnosis, clinical handover, and so on)
2. Pick **Flow** (no corrections during conversation) or **Coach** (inline corrections, labelled by category, with the wording you got wrong underlined in your transcript — and your recurring weak spots from past sessions targeted specifically)
3. Click **Start Session**
4. The AI plays its opening line through your speakers. Click **Push to talk** (or press Space) and speak. The mic stays open — click **Stop & send** when you're done, or just pause for about a second and a half and the app sends the turn itself.
5. Click **End Session** when you're done
6. The Debrief screen runs analysis: per-turn metrics, new vs recurring weak spots, suggested drills

The **Sessions** sidebar shows all your past sessions. Click a row to revisit its
debrief, or hit **Continue** to pick that conversation back up — the AI keeps the
earlier context and carries on instead of greeting you again.

The **Settings** sidebar lets you change the theme (light / dark / follow your
Mac), the LLM model, speech-to-text paths, default mode, and audio retention.

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

These are tracked for a later polish release:

- **Speech-to-text needs a manual install.** whisper.cpp and its model aren't bundled — see Step 4. Without them the Live Session screen says so instead of inventing a transcript.
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

### "Ollama doesn't have the model '...'"

Ollama is running but that model isn't pulled. Run the `ollama pull` command the
message names, or run `ollama list` and set one of those names in
**Settings > AI Model**. Remember that `:cloud` entries aren't local models.

### "Speech-to-text isn't set up yet, so the app can't hear you"

Complete Step 4, then open **Settings > Speech-to-text** and click **Auto-detect**.

### "Didn't catch any speech"

The mic opened but no audio arrived. Check System Settings → Sound → Input that
the right device is selected and its level moves when you talk.

### The conversation feels slow / choppy

The first AI reply after starting a session warms up Ollama (a few seconds). Subsequent turns are faster. If it's consistently slow, you may be running a model too big for your Mac's RAM — try `qwen2.5:3b-instruct` or `phi3:mini`.

### I want to uninstall

```bash
rm -rf EngAssistant.app
rm -rf ~/Library/Application\ Support/EngAssistant
brew uninstall ollama   # optional, if you don't use Ollama for anything else
```
