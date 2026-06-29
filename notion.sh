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
usage() {
  cat <<EOF
notion.sh — push a transcript/summary into a Notion database as a new page.

usage: $(basename "$0") <text-file> [options]

options:
  -t, --title <text>   page title (default: "Meeting <date>")
  -d, --date <iso>     Date property value (default: now, ISO 8601)
  -h, --help           show this help

Reads NOTION_TOKEN and NOTION_PARENT_DATABASE_ID from .env.

example:
  $(basename "$0") standup.summary.md -t "Standup 2026-06-29"
EOF
}

TRANSCRIPT=""
TITLE=""
DATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    -t|--title) TITLE="$2"; shift 2 ;;
    -d|--date)  DATE="$2";  shift 2 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)  TRANSCRIPT="$1"; shift ;;
  esac
done

[ -z "$TRANSCRIPT" ] && { usage >&2; exit 2; }
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

# --- build Notion blocks from Markdown ------------------------------------
# Renders a (subset of) Markdown into native Notion blocks:
#   # / ## / ###      -> heading_1 / heading_2 / heading_3
#   - [ ] / - [x]     -> to_do (unchecked / checked)
#   - or *            -> bulleted_list_item
#   ---, ***, ___     -> divider
#   **bold**          -> bold rich text (inline)
#   anything else     -> paragraph
# Long text is chunked to stay under Notion's 2000-char rich_text cap.
BLOCKS_FILE="$(mktemp)"
trap 'rm -f "$BLOCKS_FILE"' EXIT
jq -Rs '
  def chunk($n): if length==0 then empty else .[0:$n], (.[$n:]|chunk($n)) end;
  # turn a string into a rich_text array, honoring **bold** and the char cap
  def rich($s):
    [ ($s / "**")
      | to_entries[]
      | (.key % 2 == 1) as $bold
      | .value
      | select(. != "")
      | chunk(1900)
      | { type:"text",
          text:{content:.},
          annotations: (if $bold then {bold:true} else {} end) } ];
  [ split("\n")[]
    | gsub("\r$";"")
    | . as $line
    | (sub("^\\s+";"")) as $t
    | if   ($t | test("^### ")) then {object:"block", type:"heading_3", heading_3:{rich_text: rich($t[4:])}}
      elif ($t | test("^## "))  then {object:"block", type:"heading_2", heading_2:{rich_text: rich($t[3:])}}
      elif ($t | test("^# "))   then {object:"block", type:"heading_1", heading_1:{rich_text: rich($t[2:])}}
      elif ($t | test("^(---|\\*\\*\\*|___)\\s*$")) then {object:"block", type:"divider", divider:{}}
      elif ($t | test("^- \\[[ xX]\\] ")) then
            {object:"block", type:"to_do",
             to_do:{ checked: ($t | test("^- \\[[xX]\\] ")),
                     rich_text: rich($t[6:]) }}
      elif ($t | test("^[-*] ")) then
            {object:"block", type:"bulleted_list_item",
             bulleted_list_item:{rich_text: rich($t[2:])}}
      elif ($t | test("^\\s*$")) then empty
      else {object:"block", type:"paragraph", paragraph:{rich_text: rich($t)}}
      end ]
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
