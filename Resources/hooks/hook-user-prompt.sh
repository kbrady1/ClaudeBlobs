#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "UserPromptSubmit"
ensure_status_file

TS=$(now_ms)

atomic_update "$STATUS_FILE" \
  --arg status "working" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastMessage = null | .waitReason = null | .rawLastMessage = null | .toolFailure = null | .updatedAt = $ts'

# Clean up orphaned subagents stuck in permission or done states.
# At UserPromptSubmit time the previous turn is complete, so these are stale.
# If a subagent event fires later, ensure_status_file will recreate the file.
for f in "$STATUS_DIR"/*.json; do
  [ -f "$f" ] || continue
  [ "$f" = "$STATUS_FILE" ] && continue
  jq -e --arg sid "$SESSION_ID" \
    '.parentSessionId == $sid and (.status == "permission" or (.status == "waiting" and .waitReason == "done"))' \
    "$f" >/dev/null 2>&1 && rm -f "$f"
done

debug_log_result
