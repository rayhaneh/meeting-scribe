# meeting-scribe

Turn meeting recordings into transcripts (and, later, summaries in Notion) —
fully on-device, free, and private.

## Pipeline

1. **Record** a meeting (Notes / QuickTime) using a virtual audio device so the
   recording captures *both* your mic and the call audio. See [Audio setup](#audio-setup).
2. **Transcribe** the recording locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
3. _(later)_ **Summarize** and push notes to **Notion** via the Notion API.

## Install

```bash
brew install whisper-cpp ffmpeg

# download a model (base.en is a good speed/accuracy default, ~150 MB)
mkdir -p ~/.local/share/whisper
curl -L -o ~/.local/share/whisper/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

cp .env.example .env   # adjust paths if needed
```

## Usage

```bash
./transcribe.sh recording.m4a
# → writes recording.txt

./transcribe.sh recording.m4a -o transcripts/standup.txt
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
- [ ] Push transcript to Notion (Notion API)
- [ ] Summary + action items
