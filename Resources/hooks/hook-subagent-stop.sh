#!/bin/bash
INPUT=$(cat)
SUBAGENT_ID=$(echo "$INPUT" | jq -r '.subagent_id // empty')
STATUS_DIR="$HOME/.claude/agent-status"
STATUS_FILE="$STATUS_DIR/$SUBAGENT_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "SubagentStop"

[ -z "$SUBAGENT_ID" ] && exit 0
rm -f "$STATUS_FILE"

debug_log_result
