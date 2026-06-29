# meeting-scribe

Turn meeting recordings into transcripts (and, later, summaries in Notion) —
fully on-device, free, and private.

## Pipeline

1. **Record** a meeting (Notes / QuickTime) using a virtual audio device so the
   recording captures *both* your mic and the call audio. See [Audio setup](#audio-setup).
2. **Transcribe** the recording locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
3. **Summarize** into notes + action items with a local LLM via [Ollama](https://ollama.com).
4. **Push** the notes to **Notion** via the Notion API.

Everything runs on-device — no audio, transcript, or summary leaves your Mac
except the final notes you choose to send to Notion.

## Install

```bash
brew install whisper-cpp ffmpeg jq ollama

# download a whisper model (base.en is a good speed/accuracy default, ~150 MB)
mkdir -p ~/.local/share/whisper
curl -L -o ~/.local/share/whisper/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# run Ollama as a background service and pull a local LLM for summaries (~4.7 GB)
brew services start ollama
ollama pull llama3.1:8b

cp .env.example .env   # add your Notion token, adjust paths if needed
```

`brew services start ollama` registers Ollama as a launchd service, so macOS
**auto-starts it on every boot/login** — you don't need to start it again after
restarting your machine. To check it's running:

```bash
brew services list   # ollama should show "started"
ollama list          # should respond without error
```

To stop the background service: `brew services stop ollama`.

## Usage

One command — transcribe, summarize, and push to Notion:

```bash
./scribe.sh recording.m4a
./scribe.sh recording.m4a -t "Standup 2026-06-29"
./scribe.sh recording.m4a --no-notion     # stop before Notion
./scribe.sh recording.m4a --no-summary    # transcript only
```

Or run each step on its own:

```bash
./transcribe.sh recording.m4a                 # → recording.txt
./summarize.sh recording.txt                  # → recording.summary.md
./notion.sh recording.summary.md -t "Standup" # → Notion page URL
```

## Audio setup

To capture both sides of a call while wearing headphones, route system audio
into the recording with [BlackHole](https://github.com/ExistentialAudio/BlackHole):

- **Aggregate Device** (recording input): MacBook mic **first**, then BlackHole 2ch.
  Order matters — the mic must be channel 1 so a stereo recorder captures
  mic (ch 1) + call audio (ch 2).
- **Multi-Output Device** (playback): your headphones + BlackHole 2ch.
- System Settings → Sound → **Input** = the aggregate, **Output** = the multi-output.

## Roadmap

- [x] Local transcription (whisper.cpp)
- [x] Push notes to Notion (Notion API)
- [x] Summary + action items (local LLM via Ollama)
- [x] One-command pipeline (`scribe.sh`)
