#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "SessionEnd"

rm -f "$STATUS_FILE"

debug_log_result

# Clean up hook log for this session
rm -f "$_CB_HOOK_LOG_DIR/$SESSION_ID.log"
