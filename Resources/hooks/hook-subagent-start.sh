#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"

SUBAGENT_ID=$(echo "$INPUT" | jq -r '.subagent_id // empty')
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.subagent_type // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TS=$(date +%s000)

[ -z "$SUBAGENT_ID" ] && exit 0

STATUS_FILE="$STATUS_DIR/$SUBAGENT_ID.json"
TMP=$(mktemp "${STATUS_FILE}.XXXXXX") || exit 1

jq -n \
  --arg sid "$SUBAGENT_ID" \
  --arg parentSid "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg agentType "$SUBAGENT_TYPE" \
  --argjson ts "$TS" \
  '{
    sessionId: $sid,
    pid: 0,
    cwd: (if $cwd == "" then null else $cwd end),
    agentType: (if $agentType == "" then null else $agentType end),
    parentSessionId: $parentSid,
    status: "starting",
    lastMessage: null,
    lastToolUse: null,
    cmuxWorkspace: null,
    cmuxSurface: null,
    cmuxSocketPath: null,
    createdAt: $ts,
    updatedAt: $ts
  }' > "$TMP" && mv "$TMP" "$STATUS_FILE" || rm -f "$TMP"
