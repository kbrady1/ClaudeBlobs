#!/bin/bash
# Shared helper: recreates the status file if it was cleaned up.
# Expects STATUS_FILE, SESSION_ID, and INPUT to be set by the caller.
# Also provides atomic_update for safe concurrent writes.

# Atomically update a JSON file using jq. Uses a unique temp file per
# invocation to avoid races when multiple hooks fire simultaneously.
# Usage: atomic_update "$STATUS_FILE" jq-args... filter
atomic_update() {
  local target="$1"; shift
  local tmp
  tmp=$(mktemp "${target}.XXXXXX") || return 1
  if jq "$@" "$target" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$target"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Find the claude process by walking up the process tree.
find_claude_pid() {
  local current=$$
  for _ in $(seq 1 20); do
    local parent=$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ')
    [ -z "$parent" ] || [ "$parent" -le 1 ] 2>/dev/null && break
    local cmd=$(ps -o comm= -p "$parent" 2>/dev/null)
    case "$cmd" in
      */claude|claude) echo "$parent"; return 0 ;;
    esac
    current=$parent
  done
  # Fallback to $PPID if we can't find claude
  echo "$PPID"
}

ensure_status_file() {
  [ -f "$STATUS_FILE" ] && return 0

  local CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  local AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
  local PID=$(find_claude_pid)
  local TS=$(date +%s000)
  local CMUX_WS="${CMUX_WORKSPACE_ID:-}"
  local CMUX_SF="${CMUX_SURFACE_ID:-}"
  local CMUX_SOCK="${CMUX_SOCKET_PATH:-}"
  local tmp
  tmp=$(mktemp "${STATUS_FILE}.XXXXXX") || return 1
  chmod 600 "$tmp"

  jq -n \
    --arg sid "$SESSION_ID" \
    --argjson pid "$PID" \
    --arg cwd "$CWD" \
    --arg agentType "$AGENT_TYPE" \
    --arg cmuxWs "$CMUX_WS" \
    --arg cmuxSf "$CMUX_SF" \
    --arg cmuxSock "$CMUX_SOCK" \
    --argjson ts "$TS" \
    '{
      sessionId: $sid,
      pid: $pid,
      cwd: (if $cwd == "" then null else $cwd end),
      agentType: (if $agentType == "" then null else $agentType end),
      status: "working",
      lastMessage: null,
      lastToolUse: null,
      cmuxWorkspace: (if $cmuxWs == "" then null else $cmuxWs end),
      cmuxSurface: (if $cmuxSf == "" then null else $cmuxSf end),
      cmuxSocketPath: (if $cmuxSock == "" then null else $cmuxSock end),
      createdAt: $ts,
      updatedAt: $ts
    }' > "$tmp" && mv "$tmp" "$STATUS_FILE" || rm -f "$tmp"
}
