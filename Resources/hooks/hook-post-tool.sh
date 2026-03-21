#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "PostToolUse"
resolve_agent_status_file
ensure_status_file

TS=$(date +%s000)

# Don't overwrite permission/waiting if it was set in the last 2 seconds —
# PostToolUse for a previous tool can race with PermissionRequest for the next.
# Beyond 2s, let it through to avoid stale permission state.
CURRENT=$(jq -r '"\(.status // ""):\(.statusChangedAt // 0)"' "$STATUS_FILE" 2>/dev/null)
CURRENT_STATUS="${CURRENT%%:*}"
STATUS_AGE_MS=$(( TS - ${CURRENT#*:} ))

if { [ "$CURRENT_STATUS" = "permission" ] || [ "$CURRENT_STATUS" = "waiting" ]; } && [ "$STATUS_AGE_MS" -lt 2000 ]; then
  debug_log_result
  exit 0
fi

atomic_update "$STATUS_FILE" \
  --arg status "working" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .waitReason = null | .updatedAt = $ts'

debug_log_result
