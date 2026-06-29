#!/usr/bin/env bash
#
# scribe.sh — one command: recording → transcript → summary → Notion.
#
# Usage:
#   ./scribe.sh recording.m4a
#   ./scribe.sh recording.m4a -t "Standup 2026-06-29"
#   ./scribe.sh recording.m4a --no-notion        # skip the Notion push
#   ./scribe.sh recording.m4a --no-summary        # transcript only
#
# Pushes the summary (with the full transcript appended) to Notion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
scribe.sh — one command: recording → transcript → summary → Notion.

usage: $(basename "$0") <audio-file> [options]

options:
  -t, --title <text>   title for the Notion page (default: "Meeting <date>")
      --no-summary     transcript only; skip the local LLM summary
      --no-notion      stop after summarizing; don't push to Notion
  -h, --help           show this help

examples:
  $(basename "$0") recording.m4a
  $(basename "$0") recording.m4a -t "Standup 2026-06-29"
  $(basename "$0") recording.m4a --no-notion
EOF
}

INPUT=""
TITLE=""
DO_SUMMARY=1
DO_NOTION=1
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    -t|--title)    TITLE="$2"; shift 2 ;;
    --no-summary)  DO_SUMMARY=0; shift ;;
    --no-notion)   DO_NOTION=0; shift ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)  INPUT="$1"; shift ;;
  esac
done

if [ -z "$INPUT" ]; then
  usage >&2
  exit 2
fi

# 1) transcribe
TRANSCRIPT="$("$SCRIPT_DIR/transcribe.sh" "$INPUT")"

# 2) summarize (optional)
NOTION_INPUT="$TRANSCRIPT"
if [ "$DO_SUMMARY" -eq 1 ]; then
  SUMMARY="$("$SCRIPT_DIR/summarize.sh" "$TRANSCRIPT")"
  # Notion gets the summary, then the full transcript appended below it.
  COMBINED="${SUMMARY%.md}.notion.md"
  {
    cat "$SUMMARY"
    printf '\n\n---\n\n## Full Transcript\n\n'
    cat "$TRANSCRIPT"
  } > "$COMBINED"
  NOTION_INPUT="$COMBINED"
fi

# 3) push to Notion (optional)
if [ "$DO_NOTION" -eq 1 ]; then
  ARGS=("$NOTION_INPUT")
  [ -n "$TITLE" ] && ARGS+=(-t "$TITLE")
  "$SCRIPT_DIR/notion.sh" "${ARGS[@]}"
else
  echo "$NOTION_INPUT"
fi
