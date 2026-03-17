#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
ensure_status_file

LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
TS=$(date +%s000)

# Extract first sentence: up to first period, question mark, or newline, max 200 chars
FIRST_SENTENCE=$(echo "$LAST_MSG" | head -1 | cut -c1-200 | sed 's/[.?].*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
if [ -z "$FIRST_SENTENCE" ]; then
  FIRST_SENTENCE=$(echo "$LAST_MSG" | cut -c1-200)
fi

# Detect if the message contains a question
if echo "$LAST_MSG" | grep -q '?'; then
  WAIT_REASON="question"
else
  WAIT_REASON="done"
fi

atomic_update "$STATUS_FILE" \
  --arg status "waiting" \
  --arg lastMessage "$FIRST_SENTENCE" \
  --arg waitReason "$WAIT_REASON" \
  --argjson ts "$TS" \
  '.status = $status | .lastMessage = (if $lastMessage == "" then null else $lastMessage end) | .waitReason = $waitReason | .updatedAt = $ts'
