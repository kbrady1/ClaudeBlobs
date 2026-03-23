#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "PreToolUse"
resolve_agent_status_file
ensure_status_file

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
RAW_INPUT=$(echo "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
TS=$(date +%s000)

TOOL_USE_STR=$(format_tool_input "$TOOL_NAME" "$RAW_INPUT")

# Don't overwrite permission/waiting if it was set in the last 2 seconds —
# PreToolUse for a concurrent tool can race with PermissionRequest for another.
CURRENT=$(jq -r '"\(.status // ""):\(.statusChangedAt // 0)"' "$STATUS_FILE" 2>/dev/null)
CURRENT_STATUS="${CURRENT%%:*}"
STATUS_AGE_MS=$(( TS - ${CURRENT#*:} ))

if { [ "$CURRENT_STATUS" = "permission" ] || [ "$CURRENT_STATUS" = "waiting" ]; } && [ "$STATUS_AGE_MS" -lt 2000 ]; then
  debug_log_result
  exit 0
fi

atomic_update "$STATUS_FILE" \
  --arg status "working" \
  --arg toolUse "$TOOL_USE_STR" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastToolUse = $toolUse | .waitReason = null | .updatedAt = $ts'

debug_log_result
