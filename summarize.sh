#!/usr/bin/env bash
#
# summarize.sh — turn a transcript into a meeting summary + action items
# using a local LLM via Ollama, fully on-device (free, private).
#
# Usage:
#   ./summarize.sh transcript.txt
#   ./summarize.sh transcript.txt -o transcripts/standup.summary.md
#
# Output: writes a markdown summary next to the input (or to -o) and prints the path.

set -euo pipefail

# --- config (override via env or .env) -------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:8b}"

# --- args ------------------------------------------------------------------
usage() {
  cat <<EOF
summarize.sh — transcript → summary + action items, via a local LLM (Ollama).

usage: $(basename "$0") <transcript.txt> [options]

options:
  -o, --output <file>  where to write the summary (default: <input>.summary.md)
  -h, --help           show this help

Set OLLAMA_MODEL in .env to change the model (default: llama3.1:8b).

example:
  $(basename "$0") recording.txt -o transcripts/standup.summary.md
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
[ -f "$INPUT" ] || { echo "error: file not found: $INPUT" >&2; exit 1; }

# --- dependency checks -----------------------------------------------------
command -v ollama >/dev/null 2>&1 || {
  echo "error: ollama not installed (brew install ollama)" >&2
  echo "       then: ollama serve  &&  ollama pull $OLLAMA_MODEL" >&2
  exit 1
}
# is the ollama server up?
if ! ollama list >/dev/null 2>&1; then
  echo "error: ollama server not running — start it with: ollama serve" >&2
  exit 1
fi
# is the model pulled?
if ! ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$OLLAMA_MODEL"; then
  echo "error: model '$OLLAMA_MODEL' not pulled — run: ollama pull $OLLAMA_MODEL" >&2
  exit 1
fi

[ -z "$INPUT" ] && exit 2
[ -z "$OUT" ] && OUT="${INPUT%.*}.summary.md"

# --- prompt ----------------------------------------------------------------
read -r -d '' PROMPT <<'EOF' || true
You are a meeting-notes assistant. Below is a raw, possibly messy transcript of
a meeting (speaker labels may be missing). Write clean, concise notes in
Markdown with exactly these sections:

## Summary
A short paragraph (3-5 sentences) capturing what the meeting was about and the
key outcomes.

## Key Points
- Bulleted list of the most important discussion points and decisions.

## Action Items
- [ ] Each task on its own line, with the owner in **bold** if it's clear from
  the transcript (e.g. "**Alex**: send the report"). If no owner is clear, just
  state the task. If there are no action items, write "None".

Do not invent information that isn't in the transcript. Keep it tight.

--- TRANSCRIPT ---
EOF

echo "→ summarizing with $OLLAMA_MODEL (local)…" >&2

TRANSCRIPT_TEXT="$(cat "$INPUT")"
printf '%s\n%s\n' "$PROMPT" "$TRANSCRIPT_TEXT" \
  | ollama run "$OLLAMA_MODEL" > "$OUT"

echo "✓ summary: $OUT" >&2
echo "$OUT"
