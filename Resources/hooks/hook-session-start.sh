#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
chmod 700 "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "SessionStart"

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
PID=$PPID
TTY_NAME=$(ps -o tty= -p "$PID" 2>/dev/null | tr -d ' ')
TTY=$([ -n "$TTY_NAME" ] && [ "$TTY_NAME" != "??" ] && echo "/dev/$TTY_NAME" || echo "")
TS=$(date +%s000)
CMUX_WS="${CMUX_WORKSPACE_ID:-}"
CMUX_SF="${CMUX_SURFACE_ID:-}"
CMUX_SOCK="${CMUX_SOCKET_PATH:-}"

TMP=$(mktemp "${STATUS_FILE}.XXXXXX") || exit 1
chmod 600 "$TMP"

jq -n \
  --arg sid "$SESSION_ID" \
  --argjson pid "$PID" \
  --arg cwd "$CWD" \
  --arg agentType "$AGENT_TYPE" \
  --arg status "starting" \
  --arg tty "$TTY" \
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
    tty: (if $tty == "" then null else $tty end),
    cmuxWorkspace: (if $cmuxWs == "" then null else $cmuxWs end),
    cmuxSurface: (if $cmuxSf == "" then null else $cmuxSf end),
    cmuxSocketPath: (if $cmuxSock == "" then null else $cmuxSock end),
    createdAt: $ts,
    updatedAt: $ts,
    statusChangedAt: $ts
  }' > "$TMP" && mv "$TMP" "$STATUS_FILE" || rm -f "$TMP"

debug_log_result
