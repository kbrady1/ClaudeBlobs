#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/hook-ensure-status.sh"
debug_log_input "StopFailure"
resolve_agent_status_file
ensure_status_file

# Matchers per Claude Code docs: rate_limit, authentication_failed,
# oauth_org_not_allowed, billing_error, invalid_request, server_error,
# max_output_tokens, unknown. Fall back to .reason if matcher absent.
REASON=$(echo "$INPUT" | jq -r '.matcher // .reason // "unknown"')
TS=$(now_ms)

case "$REASON" in
  rate_limit)            MSG="Rate limited" ;;
  authentication_failed) MSG="Authentication failed" ;;
  oauth_org_not_allowed) MSG="Org not allowed" ;;
  billing_error)         MSG="Billing error" ;;
  invalid_request)       MSG="Invalid request" ;;
  server_error)          MSG="Server error" ;;
  max_output_tokens)     MSG="Max output tokens" ;;
  *)                     MSG="API error: $REASON" ;;
esac

atomic_update "$STATUS_FILE" \
  --arg status "waiting" \
  --arg toolFailure "error" \
  --arg lastMessage "$MSG" \
  --arg waitReason "done" \
  --argjson ts "$TS" \
  '(if .status != $status then .statusChangedAt = $ts else . end) | .status = $status | .toolFailure = $toolFailure | .lastMessage = $lastMessage | .waitReason = $waitReason | .updatedAt = $ts'

debug_log_result
