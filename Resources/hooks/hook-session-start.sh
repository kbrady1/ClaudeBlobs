#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
PID=$PPID
TS=$(date +%s000)
CMUX_WS="${CMUX_WORKSPACE_ID:-}"
CMUX_SF="${CMUX_SURFACE_ID:-}"
CMUX_SOCK="${CMUX_SOCKET_PATH:-}"

jq -n \
  --arg sid "$SESSION_ID" \
  --argjson pid "$PID" \
  --arg cwd "$CWD" \
  --arg agentType "$AGENT_TYPE" \
  --arg status "starting" \
  --arg cmuxWs "$CMUX_WS" \
  --arg cmuxSf "$CMUX_SF" \
  --arg cmuxSock "$CMUX_SOCK" \
  --argjson ts "$TS" \
  '{
    sessionId: $sid,
    pid: $pid,
    cwd: (if $cwd == "" then null else $cwd end),
    agentType: (if $agentType == "" then null else $agentType end),
    status: $status,
    lastMessage: null,
    lastToolUse: null,
    cmuxWorkspace: (if $cmuxWs == "" then null else $cmuxWs end),
    cmuxSurface: (if $cmuxSf == "" then null else $cmuxSf end),
    cmuxSocketPath: (if $cmuxSock == "" then null else $cmuxSock end),
    createdAt: $ts,
    updatedAt: $ts
  }' > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
