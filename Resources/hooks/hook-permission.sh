#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "PermissionRequest"
resolve_agent_status_file
ensure_status_file

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
RAW_INPUT=$(echo "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
TS=$(now_ms)

TOOL_USE_STR=$(format_tool_input "$TOOL_NAME" "$RAW_INPUT")
PERMISSION_KEY=$(printf '%s:%s' "$TOOL_NAME" "$RAW_INPUT" | md5 -q)

atomic_update "$STATUS_FILE" \
  --arg status "permission" \
  --arg toolUse "$TOOL_USE_STR" \
  --arg permKey "$PERMISSION_KEY" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastToolUse = $toolUse | .permissionKey = $permKey | .updatedAt = $ts'

# When a subagent needs permission, also update the parent's lastToolUse
# so the parent blob reflects the actual blocking permission.
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [ -n "$AGENT_ID" ]; then
  PARENT_FILE="$STATUS_DIR/$SESSION_ID.json"
  if [ -f "$PARENT_FILE" ]; then
    atomic_update "$PARENT_FILE" \
      --arg toolUse "$TOOL_USE_STR" \
      --arg permKey "$PERMISSION_KEY" \
      --argjson ts "$TS" \
      '.lastToolUse = $toolUse | .permissionKey = $permKey | .updatedAt = $ts'
  fi
fi

debug_log_result
