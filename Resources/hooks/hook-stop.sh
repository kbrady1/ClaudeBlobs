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
RAW_MSG=$(echo "$LAST_MSG" | head -c 2000)
TS=$(date +%s000)

# Extract first sentence: up to first period, question mark, or newline, max 200 chars
FIRST_SENTENCE=$(echo "$LAST_MSG" | head -1 | cut -c1-200 | sed 's/[.?].*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
if [ -z "$FIRST_SENTENCE" ]; then
  FIRST_SENTENCE=$(echo "$LAST_MSG" | cut -c1-200)
fi

# Detect if the agent is asking a follow-up question vs reporting completion.
HEAD=$(echo "$LAST_MSG" | head -2)
TAIL=$(echo "$LAST_MSG" | tail -c 500)
WAIT_REASON="done"

# If the first 2 lines contain a completion phrase, it's done regardless of trailing "?"
if echo "$HEAD" | grep -qiE '\b(done|all done|all set|complete|completed|finished|everything.s (set|ready|updated|in place)|changes applied)\b'; then
  WAIT_REASON="done"
elif echo "$TAIL" | sed 's/[*`_~]//g' | grep -qE '\?\s*$'; then
  WAIT_REASON="question"
elif echo "$TAIL" | grep -qiE '(shall I|should I|would you|do you want|want me to|ready to|like me to|proceed|go ahead|sound good|look right|make sense|let me know|what do you think|next question|give it a try|try (it|running|again|that)|take a look|test it|run it|check (if|whether|that))\b'; then
  WAIT_REASON="question"
fi

atomic_update "$STATUS_FILE" \
  --arg status "waiting" \
  --arg lastMessage "$FIRST_SENTENCE" \
  --arg waitReason "$WAIT_REASON" \
  --arg rawLastMessage "$RAW_MSG" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastMessage = (if $lastMessage == "" then null else $lastMessage end) | .waitReason = $waitReason | .rawLastMessage = (if $rawLastMessage == "" then null else $rawLastMessage end) | .updatedAt = $ts'
