#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "PostToolFailure"
resolve_agent_status_file
ensure_status_file

IS_INTERRUPT=$(echo "$INPUT" | jq -r '.is_interrupt // false')
TS=$(date +%s000)

if [ "$IS_INTERRUPT" = "true" ]; then
  FAILURE="interrupt"
else
  FAILURE="error"
fi

atomic_update "$STATUS_FILE" \
  --arg toolFailure "$FAILURE" \
  --argjson ts "$TS" \
  '.toolFailure = $toolFailure | .updatedAt = $ts'

debug_log_result
