#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

rm -f "$STATUS_FILE"
