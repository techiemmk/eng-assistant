# Installing Jul EngAssistant on a Mac

This guide assumes you have never used Terminal before. Every command is
something you copy and paste — you don't need to understand it to use the app.

**Time needed:** about 30 minutes, most of it waiting for downloads.
**Disk space needed:** about 8 GB.

If something doesn't work, skip to [When something goes wrong](#when-something-goes-wrong)
at the bottom. Nothing here can damage your Mac or your files.

---

## What you need before you start

- **A Mac running macOS 14 (Sonoma) or newer.** To check: click the  menu in
  the very top-left corner of your screen → **About This Mac**. If the version
  number is 14 or higher, you're fine.
- **An internet connection**, for the downloads in steps 2–5. After that the app
  works completely offline.
- **About 8 GB of free space.**

Everything this app does stays on your Mac. Your voice and your conversations
are never uploaded anywhere.

---

## What you'll be installing, in plain words

The app itself is small. Most of the download is the two pieces of artificial
intelligence that make it work, both of which run on your own Mac:

| Piece | What it does | Size |
|---|---|---|
| **Ollama** | Runs the AI that talks back to you | ~5 GB with its model |
| **whisper.cpp** | Turns your speech into text so the AI can understand you | ~150 MB with its model |
| **Homebrew** | An installer that fetches the two above for you | ~500 MB |
| **Apple Command Line Tools** | Lets your Mac build the app from its source code | ~1 GB |

---

## Step 1: Open Terminal

Terminal is an app that comes with every Mac. It lets you type instructions
instead of clicking.

1. Press **⌘ Command + Space** — a search box appears in the middle of the screen.
2. Type `Terminal`.
3. Press **Return**.

A small window opens with white or black background and some text ending in a
`$` or `%` symbol. That's it — leave this window open, you'll use it for the
next few steps.

**How to use the commands below:** click the copy button on a grey box (or
select the text and press ⌘C), click into the Terminal window, press **⌘V** to
paste, then press **Return**. Do one box at a time and wait for it to finish
before the next.

> **A note on passwords:** some steps ask for your Mac login password. When you
> type it, **nothing appears on screen** — no dots, no stars. That's normal.
> Type it and press Return.

---

## Step 2: Install Apple Command Line Tools

This lets your Mac turn the app's source code into a real application.

```bash
xcode-select --install
```

A window pops up asking if you want to install the tools. Click **Install**,
then **Agree**. It downloads about 1 GB — this takes 5–15 minutes.

**If you see** `command line tools are already installed`, you already have
them. Move on.

To check it worked, paste this:

```bash
swift --version
```

**You should see** something containing `Apple Swift version 6` or higher.

---

## Step 3: Install Homebrew

Homebrew is a tool that installs other tools. Paste this whole block:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It will explain what it's about to do and ask you to press **Return** to
continue, then ask for your Mac password.

**When it finishes**, it may print two lines beginning with `eval` and tell you
to run them. If it does, copy and run them — that's Homebrew telling your
Terminal where to find it.

To check it worked:

```bash
brew --version
```

**You should see** something like `Homebrew 4.x.x`.

---

## Step 4: Install and start the AI engine (Ollama)

Ollama is the program that runs the AI conversation partner on your Mac.

```bash
brew install ollama
```

Now start it, and **leave it running**:

```bash
ollama serve
```

**You should see** a few lines of text ending with something about *listening on
127.0.0.1:11434*. This window is now busy — it has to stay open and running
whenever you use the app.

**Open a second Terminal window** for the remaining steps: press **⌘N** while
Terminal is in front. Use the new window from here on.

> **Every time you want to use the app** you need Ollama running. If you've
> restarted your Mac, open Terminal and run `ollama serve` again first.

---

## Step 5: Download the AI's brain (the language model)

In your **new** Terminal window:

```bash
ollama pull qwen2.5:7b-instruct
```

This downloads about 4.5 GB and shows a progress bar. It takes 5–20 minutes
depending on your internet speed.

To check it worked:

```bash
ollama list
```

**You should see** `qwen2.5:7b-instruct` in the list.

> **If your Mac has 8 GB of memory or less**, or the app feels slow later, use
> the smaller model instead: `ollama pull qwen2.5:3b-instruct`. You can choose
> between installed models inside the app's Settings — you don't have to get
> this right now.

> **Important:** if you ever see a model with `:cloud` at the end of its name,
> that one runs on someone else's computer and needs a paid subscription. The
> app deliberately ignores those. You need one of the models above.

---

## Step 6: Let the app hear you (speech-to-text)

Without this step the app can still talk, but it can't understand you — it will
say so on screen rather than pretending. So this step is worth doing.

Install the listening engine:

```bash
brew install whisper-cpp
```

Then download its model. Paste this whole block at once:

```bash
mkdir -p ~/Library/Application\ Support/EngAssistant/models
curl -L -o ~/Library/Application\ Support/EngAssistant/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

This downloads about 150 MB and shows a progress bar.

The app finds both of these by itself when it starts. You don't need to
configure anything.

---

## Step 7: Build the app

Download the app's source code and build it. Paste each block separately:

```bash
cd ~/Downloads
git clone https://github.com/techiemmk/eng-assistant.git
cd eng-assistant
```

```bash
scripts/build-app.sh
```

The first build takes 2–5 minutes and prints a lot of text. That's normal.

**You should see**, at the end: `✓ Built ./EngAssistant.app`

If you see any line starting with `error:`, jump to
[When something goes wrong](#when-something-goes-wrong).

---

## Step 8: Open the app for the first time

The app isn't signed with an Apple developer certificate, so macOS will refuse
to open it the normal way the first time. This is a one-off.

1. In Terminal, run `open .` — a Finder window opens showing the project files.
2. Find **EngAssistant**.
3. **Right-click** it (or hold Control and click) and choose **Open**.
4. A warning appears saying the developer cannot be verified. Click **Open**
   again.

From now on you can open it like any other app by double-clicking.

**On first launch you'll be asked for microphone permission.** Click **OK** or
**Allow** — the app can't hear you without it.

---

## Step 9: Check the setup screen

The app shows its name for about three seconds, then a setup screen with four
checks:

| Check | What it means if it's red |
|---|---|
| **Ollama running** | Ollama isn't started. Go back to step 4 and run `ollama serve` |
| **Language model installed** | The model isn't downloaded. The message tells you the exact command to run — it's step 5 |
| **Microphone permission** | Open  → System Settings → Privacy & Security → Microphone and switch on EngAssistant |
| **Speech-to-text** *(optional)* | Step 6 wasn't done. You can still continue — the app just won't understand your speech |

Click **Re-run checks** after fixing anything. When the first three are green,
click **Get started**. You won't see this screen again.

---

## Step 10: Have your first conversation

1. You're on the **Practice** screen. The row of buttons at the top filters the
   scenarios: **Homeopathy**, **Medical**, **Networking**, **Social**,
   **Workplace**. Click one, then click a card to pick a conversation.
2. Choose a mode with the switch in the top right:
   - **Flow** — the other person stays in character and never corrects you.
     Feedback comes at the end.
   - **Coach** — you also get gentle corrections as you go, shown on screen but
     not spoken aloud. Grammar mistakes are always pointed out, and the wording
     you got wrong is underlined in your own words.
3. Click **Start session**. The other person speaks first, through your speakers.
4. Click **Push to talk** (or press the **Space** bar) and speak your reply. The
   microphone stays open — click **Stop & send** when you're done, or simply
   pause for a second and a half and it sends by itself.
5. Repeat as long as you like, then click **End session**.
6. The **Debrief** screen appears with how you did: counts for words, filler
   words and grammar slips, the patterns you keep repeating, and suggested
   things to practise. You can press **play** on any line to hear yourself back,
   and **Resolve** on a weak spot once you've fixed it so the coach stops
   bringing it up.

The **Sessions** list on the left keeps all your past conversations. Each row
can be reopened, **continued** where you left off, or deleted.

The **Settings** screen lets you switch between light and dark, choose which AI
model to use from the ones you have installed, and decide how long recordings
are kept.

---

## Making the AI sound more human (worth 2 minutes)

Out of the box the AI's voice sounds robotic. That is not the app — it's that
macOS ships only its most basic voices, and the good ones are a free optional
download most people never notice.

1. Open  → **System Settings**.
2. Go to **Accessibility** → **Spoken Content**.
3. Next to **System voice**, click the options button and choose
   **Manage Voices…** (the exact wording shifts slightly between macOS
   versions — look for a way to add or manage voices).
4. Open the **English** section. Voices are marked by quality; pick one labelled
   **Premium** if you see it, otherwise **Enhanced**. Click the download arrow.
   Each is a few hundred MB.
5. Back in Jul EngAssistant, go to **Settings → AI Voice**, click
   **Refresh voice list**, and choose the voice you just downloaded.
6. Click **Hear it** to listen to it before you start a conversation.

The difference is large — Premium voices are the natural-sounding ones. Until
you download one, the app's Settings screen will point this out.

You can also just pick a different Standard voice if you prefer a particular
accent; **Daniel** is British, **Karen** Australian, **Moira** Irish, **Rishi**
Indian.

---

## Where your files are kept

Everything lives in one folder:

```
~/Library/Application Support/EngAssistant/
```

To find it: in Finder, click **Go** in the menu bar, hold down **⌥ Option**,
click **Library**, then open **Application Support** → **EngAssistant**.

It contains your conversation history and settings (`eng-assistant.sqlite`),
your voice recordings (`audio`), and the speech-to-text model (`models`).

**To back up**, copy that whole folder somewhere safe. **To start completely
fresh**, delete it — the app rebuilds it empty on the next launch.

---

## When something goes wrong

### The app says a model isn't installed

Run `ollama list` in Terminal. If the model named in the message isn't there,
run the `ollama pull` command the message gives you. If you have a *different*
model installed, open **Settings** in the app and choose it from the list.

### "Speech-to-text isn't set up yet, so the app can't hear you"

Step 6 didn't complete. Run it again, then open **Settings → Speech-to-text**
in the app and click **Auto-detect**.

### "Didn't catch any speech"

The microphone opened but no sound arrived. Open  → System Settings → Sound →
Input and check the correct microphone is selected, and that the level bar moves
when you talk.

### The app won't open — "cannot be opened because the developer cannot be verified"

You double-clicked it. Right-click it and choose **Open** instead (step 8).

### The app opens but sits on the loading screen

Usually Ollama isn't running. Open Terminal and run `ollama serve`.

### "command not found: brew" or "command not found: swift"

That tool didn't install. Go back to step 2 (for `swift`) or step 3 (for
`brew`) and run it again, and read the final lines for an error.

### `scripts/build-app.sh` printed errors

Make sure you're in the right folder — run `cd ~/Downloads/eng-assistant` and
try again. If it still fails, run `swift --version`; if that errors, redo step 2.

### The conversation is slow or choppy

The first reply after starting a session is always slower while the AI warms up.
If it stays slow, your Mac may not have enough memory for the model. Install the
smaller one — `ollama pull qwen2.5:3b-instruct` — then pick it in **Settings**.

### I ran out of disk space

The large model is ~4.5 GB. Use the smaller one instead:
`ollama pull qwen2.5:3b-instruct` (~2 GB), pick it in **Settings**, then remove
the big one with `ollama rm qwen2.5:7b-instruct`.

---

## What the app doesn't do yet

So you know what to expect rather than hunting for a button that isn't there:

- **Speech-to-text has to be installed by hand** (step 6). It isn't bundled.
  Without it the app tells you so on screen rather than inventing a transcript.
- **No progress charts.** You get a debrief after each conversation, but there's
  no view of how you're improving over weeks.
- **No weak-spots list.** You can mark a weak spot resolved on the debrief where
  it appeared, but there's no single page listing all of them.
- **You can't write your own scenarios.** There are 21 built in, across five
  areas — Homeopathy (10), Medical (5), Networking (2), Social (2) and
  Workplace (2) — but no way to add your own yet.
- **The app isn't code-signed**, which is why macOS blocks the first launch
  (step 8).

---

## Removing everything

```bash
rm -rf ~/Downloads/eng-assistant
rm -rf ~/Library/Application\ Support/EngAssistant
brew uninstall ollama whisper-cpp
```

The second line deletes your conversation history and recordings permanently.
