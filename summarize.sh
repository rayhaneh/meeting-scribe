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
You are an expert meeting-notes analyst. Below is a raw, possibly messy
transcript of a meeting (speaker labels may be missing, words may be
mis-transcribed). Produce thorough, well-structured notes in Markdown.

Requirements:
- Be detailed and faithful. Capture EVERY distinct topic discussed, not just a
  few highlights. A reader who missed the meeting should understand what was
  said and what was decided.
- Organize the body as a numbered list of topics. Give each topic a short bold
  title. Under it, use sub-bullets for the key facts, questions raised, and
  context. When the group reached a conclusion, put it on its own line starting
  with "**Decision:**".
- Preserve concrete specifics: names, numbers, dates, deadlines, systems,
  tools, and account/error counts. Do not round away or drop details.
- Frame topics around the actual questions or issues discussed when natural
  (e.g. "How are rejected accounts communicated?").

Structure:

## Summary
2-4 sentences on what the meeting was about and the main outcomes.

## Discussion
1. **Topic title**
   - detail
   - **Decision:** ... (only when a decision was actually made)
2. **Next topic**
   - ...
(continue for every topic covered)

## Action Items
Group by owner. For each person who has tasks, add a "### Name" heading, then
list their tasks as checkboxes:
### Alex
- [ ] task description
- [ ] another task
(If an action item has no clear owner, put it under "### Unassigned".)

Rules:
- Use ONLY information present in the transcript. Never invent facts, names, or
  numbers. If something is unclear, omit it rather than guessing.
- Output Markdown only — no preamble, no "Here are the notes", just the notes.

--- TRANSCRIPT ---
EOF

echo "→ summarizing with $OLLAMA_MODEL (local)…" >&2

command -v jq >/dev/null 2>&1 || { echo "error: jq required (brew install jq)" >&2; exit 1; }

# Use Ollama's HTTP API (not `ollama run`) so the output is clean text rather
# than a TTY stream littered with cursor/erase escape codes.
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

REQ=$(jq -n \
  --arg model "$OLLAMA_MODEL" \
  --arg prompt "$PROMPT" \
  --rawfile transcript "$INPUT" \
  '{model:$model, stream:false, prompt:($prompt + "\n" + $transcript)}')

RESP=$(curl -s "$OLLAMA_HOST/api/generate" -d "$REQ")
SUMMARY_TEXT=$(printf '%s' "$RESP" | jq -r '.response // empty')

if [ -z "$SUMMARY_TEXT" ]; then
  echo "✗ summarization failed:" >&2
  printf '%s' "$RESP" | jq -r '.error // .' >&2 2>/dev/null || printf '%s\n' "$RESP" >&2
  exit 1
fi

printf '%s\n' "$SUMMARY_TEXT" > "$OUT"

echo "✓ summary: $OUT" >&2
echo "$OUT"
