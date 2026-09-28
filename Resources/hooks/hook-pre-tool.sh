#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "PreToolUse"
resolve_agent_status_file
ensure_status_file

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
RAW_INPUT=$(echo "$INPUT" | jq -c '.tool_input // empty' 2>/dev/null)
TS=$(now_ms)

TOOL_USE_STR=$(format_tool_input "$TOOL_NAME" "$RAW_INPUT")
QUESTIONS_JSON=$(extract_pending_questions "$TOOL_NAME")

# AskUserQuestion and ExitPlanMode block the turn until answered, so there is
# no later Stop event to capture the reasoning that led up to them the way
# hook-stop.sh normally does. Recover it here from the transcript so the
# Conductor can show the full context around the question, not just the
# question itself.
CONTEXT_LAST_MESSAGE=""
CONTEXT_RAW_MESSAGE=""
if [ "$TOOL_NAME" = "AskUserQuestion" ] || [ "$TOOL_NAME" = "ExitPlanMode" ]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
  PRECEDING_TEXT=$(extract_preceding_text "$TRANSCRIPT_PATH")
  if [ -n "$PRECEDING_TEXT" ]; then
    CONTEXT_RAW_MESSAGE=$(printf '%s' "$PRECEDING_TEXT" | jq -Rrs '.[:12000]')
    CONTEXT_LAST_MESSAGE=$(first_sentence_from_message "$(last_paragraph "$PRECEDING_TEXT")")
  fi
fi

# Monitor/TaskStop flip a durable flag instead of relying on lastToolUse, which
# gets overwritten by the very next tool call in the same turn.
#
# A non-persistent Monitor (the default) self-terminates at its timeout_ms with
# no obligation on the agent to ever call TaskStop — that's expected, not a
# missed cleanup step. So we record a hard expiry (now + timeout_ms) alongside
# the flag; the app treats the flag as stale once that deadline passes. A
# persistent Monitor has no timeout and stays active until an explicit
# TaskStop, so it gets no expiry.
MONITOR_ACTIVE_FILTER="."
# A persistent Monitor has no timeout_ms, but still gets a ceiling: if the
# agent never calls TaskStop (forgets, gets interrupted, branches away), this
# bounds how long monitorActive can hide a session instead of staying stuck forever.
PERSISTENT_MONITOR_CEILING_MS=$((4 * 60 * 60 * 1000))
if [ "$TOOL_NAME" = "Monitor" ]; then
  IS_PERSISTENT=$(echo "$RAW_INPUT" | jq -r 'if .persistent == true then "true" else "false" end' 2>/dev/null)
  if [ "$IS_PERSISTENT" = "true" ]; then
    MONITOR_ACTIVE_FILTER=".monitorActive = true | .monitorExpiresAt = $((TS + PERSISTENT_MONITOR_CEILING_MS))"
  else
    TIMEOUT_MS=$(echo "$RAW_INPUT" | jq -r '.timeout_ms // 300000' 2>/dev/null)
    case "$TIMEOUT_MS" in ''|*[!0-9]*) TIMEOUT_MS=300000 ;; esac
    MONITOR_ACTIVE_FILTER=".monitorActive = true | .monitorExpiresAt = $((TS + TIMEOUT_MS))"
  fi
elif [ "$TOOL_NAME" = "TaskStop" ]; then
  MONITOR_ACTIVE_FILTER=".monitorActive = false | .monitorExpiresAt = null"
elif [ "$TOOL_NAME" = "ScheduleWakeup" ]; then
  # Same durable-flag treatment as Monitor, and for the same reason: a /loop
  # session calls ScheduleWakeup and then keeps working (Bash, Agent, Edit), so
  # by the end of the turn lastToolUse names the last tool, not the wakeup.
  # Reading the schedule off lastToolUse therefore misses every loop that does
  # any work after scheduling — which is all of them.
  #
  # `stop: true` ends the loop, so it clears the flag. Otherwise the wakeup is
  # due at now + delaySeconds; the app treats the flag as stale past that, with
  # a grace window so a session is not surfaced the instant it is due.
  WAKEUP_STOP=$(echo "$RAW_INPUT" | jq -r 'if .stop == true then "true" else "false" end' 2>/dev/null)
  if [ "$WAKEUP_STOP" = "true" ]; then
    MONITOR_ACTIVE_FILTER=".scheduledWakeupAt = null"
  else
    DELAY_S=$(echo "$RAW_INPUT" | jq -r '.delaySeconds // 0' 2>/dev/null)
    case "$DELAY_S" in ''|*[!0-9]*) DELAY_S=0 ;; esac
    # The runtime clamps delaySeconds to [60, 3600]; mirror the ceiling so a
    # bad value cannot hide a session for an unbounded stretch.
    [ "$DELAY_S" -gt 3600 ] && DELAY_S=3600
    [ "$DELAY_S" -lt 60 ] && DELAY_S=60
    MONITOR_ACTIVE_FILTER=".scheduledWakeupAt = $((TS + DELAY_S * 1000))"
  fi
fi

# Never overwrite permission — PreToolUse fires BEFORE PermissionRequest for
# the same tool, so it can never be the signal that permission was granted.
# That signal is PostToolUse.
CURRENT_STATUS=$(jq -r '.status // empty' "$STATUS_FILE" 2>/dev/null)

if [ "$CURRENT_STATUS" = "permission" ]; then
  STORED_PERM_TOOL=$(jq -r '.permissionTool // empty' "$STATUS_FILE" 2>/dev/null)
  # ExitPlanMode and AskUserQuestion block the turn until answered — if another
  # tool is now firing, they were already answered, so clear the permission
  # state. (AskUserQuestion can't self-clear via PostToolUse's key check; see
  # hook-post-tool.sh.)
  if [ "$STORED_PERM_TOOL" != "ExitPlanMode" ] && [ "$STORED_PERM_TOOL" != "AskUserQuestion" ]; then
    debug_log_result
    exit 0
  fi
fi

atomic_update "$STATUS_FILE" \
  --arg status "working" \
  --arg toolUse "$TOOL_USE_STR" \
  --argjson questions "$QUESTIONS_JSON" \
  --arg lastMessage "$CONTEXT_LAST_MESSAGE" \
  --arg rawLastMessage "$CONTEXT_RAW_MESSAGE" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .lastToolUse = $toolUse | .pendingQuestions = $questions | .waitReason = null | .toolFailure = null | .lastMessage = (if $lastMessage == "" then null else $lastMessage end) | .rawLastMessage = (if $rawLastMessage == "" then null else $rawLastMessage end) | .updatedAt = $ts | '"$MONITOR_ACTIVE_FILTER"

debug_log_result
