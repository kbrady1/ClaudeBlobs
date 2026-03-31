#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "Notification"
resolve_agent_status_file
ensure_status_file

TS=$(now_ms)
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')

case "$NOTIFICATION_TYPE" in
  permission_prompt)
    # No-op: PermissionRequest hook already sets status="permission" on the correct
    # (subagent) file. This Notification event arrives without agent_id, so it would
    # hit the parent session file — which has no corresponding PostToolUse to clear it,
    # causing the parent blob to get permanently stuck in permission state.
    ;;
  idle_prompt)
    # Ignored — Stop hook already sets the correct waiting status and waitReason
    ;;
  *)
    # Other notifications (auth_success, etc.) — mark working unless in a protected state
    CURRENT_STATUS=$(jq -r '.status // empty' "$STATUS_FILE" 2>/dev/null)
    if [ "$CURRENT_STATUS" != "permission" ] && [ "$CURRENT_STATUS" != "waiting" ]; then
      atomic_update "$STATUS_FILE" \
        --arg status "working" \
        --argjson ts "$TS" \
        '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .updatedAt = $ts | .waitReason = null'
    fi
    ;;
esac

debug_log_result
