#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "TaskCompleted"
resolve_agent_status_file
ensure_status_file

TS=$(now_ms)

atomic_update "$STATUS_FILE" \
  --argjson ts "$TS" \
  '.taskCompletedAt = $ts | .updatedAt = $ts'

debug_log_result
