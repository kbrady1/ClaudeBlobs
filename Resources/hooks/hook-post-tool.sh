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

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
RAW_INPUT=$(echo "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
TS=$(now_ms)

# Never overwrite waiting — only user-prompt should clear that.
# For permission: only clear it if this PostToolUse is for the exact tool that
# was blocked (matching permissionKey). The flow is:
#   PreToolUse → PermissionRequest → [user grants] → PostToolUse
# So PostToolUse with a matching key means permission was granted and the tool ran.
# Sibling tools have a different key and won't clobber.
CURRENT_STATUS=$(jq -r '.status // empty' "$STATUS_FILE" 2>/dev/null)

if [ "$CURRENT_STATUS" = "waiting" ]; then
  debug_log_result
  exit 0
fi

if [ "$CURRENT_STATUS" = "permission" ]; then
  STORED_KEY=$(jq -r '.permissionKey // empty' "$STATUS_FILE" 2>/dev/null)
  MY_KEY=$(printf '%s:%s' "$TOOL_NAME" "$RAW_INPUT" | md5 -q)
  if [ "$MY_KEY" != "$STORED_KEY" ]; then
    debug_log_result
    exit 0
  fi
fi

atomic_update "$STATUS_FILE" \
  --arg status "working" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .waitReason = null | .updatedAt = $ts'

debug_log_result
