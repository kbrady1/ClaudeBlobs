#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

[ ! -f "$STATUS_FILE" ] && exit 0

LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
TS=$(date +%s000)

# Extract first sentence: up to first period, question mark, or newline, max 200 chars
FIRST_SENTENCE=$(echo "$LAST_MSG" | head -1 | cut -c1-200 | sed 's/[.?].*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
if [ -z "$FIRST_SENTENCE" ]; then
  FIRST_SENTENCE=$(echo "$LAST_MSG" | cut -c1-200)
fi

jq \
  --arg status "waiting" \
  --arg lastMessage "$FIRST_SENTENCE" \
  --argjson ts "$TS" \
  '.status = $status | .lastMessage = (if $lastMessage == "" then null else $lastMessage end) | .updatedAt = $ts' \
  "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
