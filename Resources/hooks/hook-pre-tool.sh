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
TS=$(now_ms)

TOOL_USE_STR=$(format_tool_input "$TOOL_NAME" "$RAW_INPUT")

# Monitor/TaskStop flip a durable flag instead of relying on lastToolUse, which
# gets overwritten by the very next tool call in the same turn.
#
# A non-persistent Monitor (the default) self-terminates at its timeout_ms with
# no obligation on the agent to ever call TaskStop — that's expected, not a
# missed cleanup step. So we record a hard expiry (now + timeout_ms) alongside
# the flag; the app treats the flag as stale once that deadline passes. A
# persistent Monitor has no timeout and stays active until an explicit
# TaskStop, so it gets no expiry.
MONITOR_ACTIVE_FILTER="."
if [ "$TOOL_NAME" = "Monitor" ]; then
  IS_PERSISTENT=$(echo "$RAW_INPUT" | jq -r 'if .persistent == true then "true" else "false" end' 2>/dev/null)
  if [ "$IS_PERSISTENT" = "true" ]; then
    MONITOR_ACTIVE_FILTER=".monitorActive = true | .monitorExpiresAt = null"
  else
    TIMEOUT_MS=$(echo "$RAW_INPUT" | jq -r '.timeout_ms // 300000' 2>/dev/null)
    case "$TIMEOUT_MS" in ''|*[!0-9]*) TIMEOUT_MS=300000 ;; esac
    MONITOR_ACTIVE_FILTER=".monitorActive = true | .monitorExpiresAt = $((TS + TIMEOUT_MS))"
  fi
elif [ "$TOOL_NAME" = "TaskStop" ]; then
  MONITOR_ACTIVE_FILTER=".monitorActive = false | .monitorExpiresAt = null"
fi

# Never overwrite permission — PreToolUse fires BEFORE PermissionRequest for
# the same tool, so it can never be the signal that permission was granted.
# That signal is PostToolUse.
CURRENT_STATUS=$(jq -r '.status // empty' "$STATUS_FILE" 2>/dev/null)

if [ "$CURRENT_STATUS" = "permission" ]; then
  STORED_PERM_TOOL=$(jq -r '.permissionTool // empty' "$STATUS_FILE" 2>/dev/null)
  # ExitPlanMode and AskUserQuestion block the turn until answered — if another
  # tool is now firing, they were already answered, so clear the permission
  # state. (AskUserQuestion can't self-clear via PostToolUse's key check; see
  # hook-post-tool.sh.)
  if [ "$STORED_PERM_TOOL" != "ExitPlanMode" ] && [ "$STORED_PERM_TOOL" != "AskUserQuestion" ]; then
    debug_log_result
    exit 0
  fi
fi

atomic_update "$STATUS_FILE" \
  --arg status "working" \
  --arg toolUse "$TOOL_USE_STR" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastToolUse = $toolUse | .waitReason = null | .toolFailure = null | .lastMessage = null | .rawLastMessage = null | .updatedAt = $ts | '"$MONITOR_ACTIVE_FILTER"

debug_log_result
