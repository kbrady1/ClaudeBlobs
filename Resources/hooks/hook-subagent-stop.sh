#!/bin/bash
INPUT=$(cat)
SUBAGENT_ID=$(echo "$INPUT" | jq -r '.subagent_id // empty')
STATUS_DIR="$HOME/.claude/agent-status"

[ -z "$SUBAGENT_ID" ] && exit 0
rm -f "$STATUS_DIR/$SUBAGENT_ID.json"
