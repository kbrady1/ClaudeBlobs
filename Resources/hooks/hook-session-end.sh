#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "SessionEnd"

rm -f "$STATUS_FILE"

# Cascade: remove any subagent status files whose parentSessionId matches this session.
# The SubagentStop hook is not guaranteed to fire (subagent crash, parent compaction,
# user escape) so SessionEnd is our backstop for orphaned children.
if [ -d "$STATUS_DIR" ]; then
  for f in "$STATUS_DIR"/*.json; do
    [ -f "$f" ] || continue
    parent=$(jq -r '.parentSessionId // empty' "$f" 2>/dev/null)
    if [ "$parent" = "$SESSION_ID" ]; then
      rm -f "$f"
      debug_log "[SessionEnd] cascaded delete: $(basename "$f")"
    fi
  done
fi

debug_log_result

# Clean up hook log for this session
rm -f "$_CB_HOOK_LOG_DIR/$SESSION_ID.log"
