#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "Stop"
resolve_agent_status_file
ensure_status_file

LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
RAW_MSG=$(echo "$LAST_MSG" | head -c 2000)
TS=$(now_ms)

# Strip markdown formatting and extract a clean first sentence.
# 1. Remove markdown: headings, bold, backticks, bullets
CLEAN_MSG=$(echo "$LAST_MSG" | sed 's/^#\{1,6\}[[:space:]]*//' | sed 's/\*\*//g' | sed 's/`//g' | sed 's/^- //')

# 2. Skip filler preambles on line 1 — if line 1 is short filler, try line 2
LINE1=$(echo "$CLEAN_MSG" | head -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
if echo "$LINE1" | grep -qiE '^(good|great|now I have|perfect|excellent|sure|okay|alright|here|let me)[,. !]'; then
  LINE2=$(echo "$CLEAN_MSG" | tail -n +2 | grep -m1 '[^[:space:]]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [ -n "$LINE2" ] && [ ${#LINE2} -gt 5 ]; then
    LINE1="$LINE2"
  fi
fi

# 3. Truncate at sentence boundary (". " followed by uppercase) but not inside URLs
#    The negative lookbehind avoids splitting on "https://foo.com. Next" style
FIRST_SENTENCE=$(echo "$LINE1" | cut -c1-200 | sed 's|\([^A-Z:/]\)\. [A-Z].*|\1|' | sed 's/[[:space:]]*$//')
if [ -z "$FIRST_SENTENCE" ]; then
  FIRST_SENTENCE=$(echo "$LAST_MSG" | sed 's/`//g' | cut -c1-200)
fi

# Detect if the agent is asking a follow-up question vs reporting completion.
HEAD=$(echo "$LAST_MSG" | head -2)
TAIL=$(echo "$LAST_MSG" | tail -c 500)
WAIT_REASON="done"

# If the message contains a question indicator, it's a question regardless of completion phrases
if echo "$HEAD" | grep -qiE '(last question|next question|one more question|quick question)\b'; then
  WAIT_REASON="question"
# If the first 2 lines contain a completion phrase, it's done regardless of trailing "?"
elif echo "$HEAD" | grep -qiE '\b(done|all done|all set|complete|completed|finished|everything.s (set|ready|updated|in place)|changes applied)\b'; then
  WAIT_REASON="done"
elif echo "$TAIL" | sed 's/[*`_~]//g' | grep -qE '\?\s*$'; then
  WAIT_REASON="question"
elif echo "$TAIL" | grep -qiE '(shall I|should I|would you|do you want|want me to|ready to|like me to|proceed|go ahead|sound good|look right|make sense|let me know|what do you think|next question|give it a try|try (it|running|again|that)|take a look|test it|run it|check (if|whether|that)|I.d recommend|which (would|do|should)|option [A-Z]\b)\b'; then
  WAIT_REASON="question"
fi

atomic_update "$STATUS_FILE" \
  --arg status "waiting" \
  --arg lastMessage "$FIRST_SENTENCE" \
  --arg waitReason "$WAIT_REASON" \
  --arg rawLastMessage "$RAW_MSG" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastMessage = (if $lastMessage == "" then null else $lastMessage end) | .waitReason = $waitReason | .rawLastMessage = (if $rawLastMessage == "" then null else $rawLastMessage end) | .updatedAt = $ts'

debug_log_result
