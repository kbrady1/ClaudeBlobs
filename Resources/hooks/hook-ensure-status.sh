#!/bin/bash
# Shared helper: recreates the status file if it was cleaned up.
# Expects STATUS_FILE, SESSION_ID, and INPUT to be set by the caller.
# Also provides atomic_update for safe concurrent writes.

# --- Debug logging ---
_CB_DEBUG_FLAG="$HOME/Library/Logs/ClaudeBlobs/.debug-enabled"
_CB_HOOK_LOG_DIR="$HOME/Library/Logs/ClaudeBlobs/hooks"
_CB_HOOK_LOG=""
_CB_HOOK_NAME=""

debug_log() {
  [ -n "$_CB_HOOK_LOG" ] || return 0
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$ts] $1" >> "$_CB_HOOK_LOG"
}

debug_log_input() {
  _CB_HOOK_NAME="$1"
  [ -f "$_CB_DEBUG_FLAG" ] || return 0
  local sid
  sid=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  [ -z "$sid" ] && return 0
  mkdir -p "$_CB_HOOK_LOG_DIR"
  _CB_HOOK_LOG="$_CB_HOOK_LOG_DIR/$sid.log"
  local pid cwd
  pid=$(echo "$INPUT" | jq -r '.pid // empty' 2>/dev/null)
  cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  debug_log "[$1] sid=$sid pid=$pid cwd=$cwd INPUT:"
  echo "$INPUT" >> "$_CB_HOOK_LOG"
  echo "" >> "$_CB_HOOK_LOG"
}

debug_log_result() {
  [ -n "$_CB_HOOK_LOG" ] || return 0
  if [ -n "$STATUS_FILE" ] && [ -f "$STATUS_FILE" ]; then
    local sid pid cwd
    sid=$(jq -r '.sessionId // empty' "$STATUS_FILE" 2>/dev/null)
    pid=$(jq -r '.pid // empty' "$STATUS_FILE" 2>/dev/null)
    cwd=$(jq -r '.cwd // empty' "$STATUS_FILE" 2>/dev/null)
    debug_log "[$_CB_HOOK_NAME] sid=$sid pid=$pid cwd=$cwd RESULT:"
    cat "$STATUS_FILE" >> "$_CB_HOOK_LOG"
  else
    debug_log "[$_CB_HOOK_NAME] RESULT: (status file deleted)"
  fi
  echo "" >> "$_CB_HOOK_LOG"
}

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

# Millisecond-precision timestamp. macOS date(1) lacks %N, so use perl.
now_ms() {
  perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'
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

# Format tool input for human-readable display.
# Usage: format_tool_input TOOL_NAME RAW_INPUT_JSON
# Outputs "ToolName: summary" or just "ToolName" if extraction fails.
format_tool_input() {
  local tool_name="$1"
  local raw_json="$2"

  # If the input is a plain string (not a JSON object), use it directly
  local input_type
  input_type=$(echo "$raw_json" | jq -r 'type' 2>/dev/null)
  if [ "$input_type" = "string" ]; then
    local str_val
    str_val=$(echo "$raw_json" | jq -r '.' 2>/dev/null | cut -c1-80)
    if [ -n "$str_val" ] && [ "$str_val" != "null" ]; then
      echo "${tool_name}: ${str_val}"
    else
      echo "$tool_name"
    fi
    return
  fi

  # Try to extract a human-readable summary based on tool type
  local summary=""
  case "$tool_name" in
    Bash)
      summary=$(echo "$raw_json" | jq -r '.command // empty' 2>/dev/null | cut -c1-80)
      ;;
    Edit|Write|Read)
      summary=$(echo "$raw_json" | jq -r '.file_path // empty' 2>/dev/null | xargs basename 2>/dev/null)
      ;;
    Grep)
      summary=$(echo "$raw_json" | jq -r '.pattern // empty' 2>/dev/null | cut -c1-80)
      ;;
    Glob)
      summary=$(echo "$raw_json" | jq -r '.pattern // empty' 2>/dev/null | cut -c1-80)
      ;;
    Agent)
      summary=$(echo "$raw_json" | jq -r '.description // empty' 2>/dev/null | cut -c1-80)
      ;;
    WebSearch)
      summary=$(echo "$raw_json" | jq -r '.query // empty' 2>/dev/null | cut -c1-80)
      ;;
    WebFetch)
      summary=$(echo "$raw_json" | jq -r '.url // empty' 2>/dev/null | cut -c1-80)
      ;;
    NotebookEdit)
      summary=$(echo "$raw_json" | jq -r '.notebook // empty' 2>/dev/null | xargs basename 2>/dev/null)
      ;;
    *)
      # Fallback: stringify and truncate
      summary=$(echo "$raw_json" | jq -r 'if type == "object" then tostring else . end' 2>/dev/null | cut -c1-80)
      ;;
  esac

  if [ -n "$summary" ] && [ "$summary" != "null" ] && [ "$summary" != "{}" ]; then
    echo "${tool_name}: ${summary}"
  else
    echo "$tool_name"
  fi
}

# Route to subagent status file when agent_id is present in input.
# Call after STATUS_FILE is set. Overrides STATUS_FILE if the event
# belongs to a subagent rather than the parent session.
resolve_agent_status_file() {
  local agent_id
  agent_id=$(echo "$INPUT" | jq -r '.agent_id // empty')
  if [ -n "$agent_id" ]; then
    STATUS_FILE="$STATUS_DIR/$agent_id.json"
  fi
}

ensure_status_file() {
  [ -f "$STATUS_FILE" ] && return 0

  local CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
  local AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
  local PID=$(find_claude_pid)
  local TTY_NAME=$(ps -o tty= -p "$PID" 2>/dev/null | tr -d ' ')
  local TTY=$([ -n "$TTY_NAME" ] && [ "$TTY_NAME" != "??" ] && echo "/dev/$TTY_NAME" || echo "")
  local TS=$(now_ms)
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
      status: "working",
      lastMessage: null,
      lastToolUse: null,
      tty: (if $tty == "" then null else $tty end),
      cmuxWorkspace: (if $cmuxWs == "" then null else $cmuxWs end),
      cmuxSurface: (if $cmuxSf == "" then null else $cmuxSf end),
      cmuxSocketPath: (if $cmuxSock == "" then null else $cmuxSock end),
      createdAt: $ts,
      updatedAt: $ts,
      statusChangedAt: $ts
    }' > "$tmp" && mv "$tmp" "$STATUS_FILE" || rm -f "$tmp"
}
