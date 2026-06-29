#!/usr/bin/env bash
#
# transcribe.sh — turn a meeting recording into a plain-text transcript
# using whisper.cpp, fully on-device (free, private).
#
# Usage:
#   ./transcribe.sh recording.m4a
#   ./transcribe.sh recording.m4a -o notes/standup.txt
#
# Output: writes a .txt next to the input (or to -o) and prints the path.

set -euo pipefail

# --- config (override via env or .env) -------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

WHISPER_BIN="${WHISPER_BIN:-whisper-cli}"
MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper/ggml-base.en.bin}"

# --- args ------------------------------------------------------------------
usage() {
  cat <<EOF
transcribe.sh — turn a meeting recording into a plain-text transcript (whisper.cpp).

usage: $(basename "$0") <audio-file> [options]

options:
  -o, --output <file>  where to write the transcript (default: <input>.txt)
  -h, --help           show this help

example:
  $(basename "$0") recording.m4a -o transcripts/standup.txt
EOF
}

INPUT=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage; exit 0 ;;
    -o|--output) OUT="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)  INPUT="$1"; shift ;;
  esac
done

if [ -z "$INPUT" ]; then
  usage >&2
  exit 2
fi
if [ ! -f "$INPUT" ]; then
  echo "error: file not found: $INPUT" >&2
  exit 1
fi

# --- dependency checks -----------------------------------------------------
command -v ffmpeg >/dev/null 2>&1 || { echo "error: ffmpeg not installed (brew install ffmpeg)" >&2; exit 1; }
command -v "$WHISPER_BIN" >/dev/null 2>&1 || { echo "error: $WHISPER_BIN not found (brew install whisper-cpp)" >&2; exit 1; }
if [ ! -f "$MODEL" ]; then
  echo "error: whisper model not found at: $MODEL" >&2
  echo "       download one, e.g.:" >&2
  echo "       mkdir -p \"$(dirname "$MODEL")\" && curl -L -o \"$MODEL\" \\" >&2
  echo "         https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" >&2
  exit 1
fi

# --- transcode to 16kHz mono wav (what whisper.cpp expects) ----------------
TMPWAV="$(mktemp -t scribe).wav"
trap 'rm -f "$TMPWAV"' EXIT
echo "→ converting audio…" >&2
ffmpeg -nostdin -loglevel error -y -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TMPWAV"

# --- transcribe ------------------------------------------------------------
[ -z "$OUT" ] && OUT="${INPUT%.*}.txt"
OUT_BASE="${OUT%.txt}"
echo "→ transcribing with $(basename "$MODEL")…" >&2
"$WHISPER_BIN" -m "$MODEL" -f "$TMPWAV" -otxt -of "$OUT_BASE" >/dev/null 2>&1

echo "✓ transcript: ${OUT_BASE}.txt" >&2
echo "${OUT_BASE}.txt"
