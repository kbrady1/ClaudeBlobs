#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
ensure_status_file

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty | if type == "object" then tostring else . end' 2>/dev/null | cut -c1-80)
TS=$(date +%s000)

if [ -n "$TOOL_INPUT" ] && [ "$TOOL_INPUT" != "null" ] && [ "$TOOL_INPUT" != "{}" ]; then
  TOOL_USE_STR="${TOOL_NAME}: ${TOOL_INPUT}"
else
  TOOL_USE_STR="$TOOL_NAME"
fi

jq \
  --arg status "permission" \
  --arg toolUse "$TOOL_USE_STR" \
  --argjson ts "$TS" \
  '.status = $status | .lastToolUse = $toolUse | .updatedAt = $ts' \
  "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
