#!/usr/bin/env bash
#
# notion.sh — push a transcript into a Notion database as a new page.
#
# Usage:
#   ./notion.sh transcript.txt
#   ./notion.sh transcript.txt -t "Standup 2026-06-27"
#
# Reads NOTION_TOKEN and NOTION_PARENT_DATABASE_ID from .env.
# Prints the URL of the created page.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

# --- args ------------------------------------------------------------------
TRANSCRIPT="${1:-}"
TITLE=""
DATE=""
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--title) TITLE="$2"; shift 2 ;;
    -d|--date)  DATE="$2";  shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -z "$TRANSCRIPT" ] && { echo "usage: $0 <transcript.txt> [-t title]" >&2; exit 2; }
[ -f "$TRANSCRIPT" ] || { echo "error: not found: $TRANSCRIPT" >&2; exit 1; }
: "${NOTION_TOKEN:?set NOTION_TOKEN in .env}"
: "${NOTION_PARENT_DATABASE_ID:?set NOTION_PARENT_DATABASE_ID in .env}"
command -v jq >/dev/null 2>&1 || { echo "error: jq required (brew install jq)" >&2; exit 1; }

[ -z "$TITLE" ] && TITLE="Meeting $(date '+%Y-%m-%d %H:%M')"
# ISO 8601 with timezone offset (e.g. 2026-06-27T17:33:00-07:00)
[ -z "$DATE" ] && DATE="$(date +%Y-%m-%dT%H:%M:%S)$(date +%z | sed 's/\(..\)$/:\1/')"

API="https://api.notion.com/v1"
H_AUTH="Authorization: Bearer ${NOTION_TOKEN}"
H_VER="Notion-Version: 2022-06-28"
H_CT="Content-Type: application/json"

# --- build paragraph blocks from transcript (Notion caps rich_text at 2000) -
BLOCKS_FILE="$(mktemp)"
trap 'rm -f "$BLOCKS_FILE"' EXIT
jq -Rs '
  def chunk($n): if length==0 then empty else .[0:$n], (.[$n:]|chunk($n)) end;
  [ (sub("^\\s+";"") | sub("\\s+$";""))
    | chunk(1900)
    | {object:"block", type:"paragraph",
       paragraph:{rich_text:[{type:"text", text:{content:.}}]}} ]
' "$TRANSCRIPT" > "$BLOCKS_FILE"

TOTAL=$(jq 'length' "$BLOCKS_FILE")
[ "$TOTAL" -eq 0 ] && { echo "error: transcript is empty" >&2; exit 1; }
echo "→ creating Notion page \"$TITLE\" ($TOTAL block(s))…" >&2

# --- create page with first 100 blocks (Notion children cap) ---------------
PAYLOAD=$(jq -c \
  --arg db "$NOTION_PARENT_DATABASE_ID" \
  --arg title "$TITLE" \
  --arg date "$DATE" '
  {parent:{database_id:$db},
   properties:{
     Title:{title:[{text:{content:$title}}]},
     Date:{date:{start:$date}}
   },
   children: .[0:100]}' "$BLOCKS_FILE")

RESP=$(curl -s -X POST "$API/pages" -H "$H_AUTH" -H "$H_VER" -H "$H_CT" -d "$PAYLOAD")
PAGE_ID=$(echo "$RESP" | jq -r '.id // empty')
if [ -z "$PAGE_ID" ]; then
  echo "✗ failed to create page:" >&2
  echo "$RESP" | jq '{code, message}' >&2 2>/dev/null || echo "$RESP" >&2
  exit 1
fi

# --- append remaining blocks in batches of 100 -----------------------------
OFFSET=100
while [ "$OFFSET" -lt "$TOTAL" ]; do
  BATCH=$(jq -c --argjson o "$OFFSET" '{children: .[$o:($o+100)]}' "$BLOCKS_FILE")
  curl -s -X PATCH "$API/blocks/$PAGE_ID/children" \
    -H "$H_AUTH" -H "$H_VER" -H "$H_CT" -d "$BATCH" >/dev/null
  OFFSET=$((OFFSET+100))
done

URL="https://www.notion.so/${PAGE_ID//-/}"
echo "✓ created: $URL" >&2
echo "$URL"
