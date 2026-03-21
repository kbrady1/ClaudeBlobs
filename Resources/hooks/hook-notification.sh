#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "Notification"
ensure_status_file

CURRENT_STATUS=$(jq -r '.status // empty' "$STATUS_FILE" 2>/dev/null)
TS=$(date +%s000)

# Don't overwrite permission or waiting status — notifications often fire right after these
if [ "$CURRENT_STATUS" != "permission" ] && [ "$CURRENT_STATUS" != "waiting" ]; then
  atomic_update "$STATUS_FILE" \
    --arg status "working" \
    --argjson ts "$TS" \
    '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .updatedAt = $ts | .waitReason = null'
fi

debug_log_result
