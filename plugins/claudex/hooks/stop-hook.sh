#!/usr/bin/env bash
# Claudex — Stop Hook
#
# Manages the impl loop lifecycle:
#   Phase: impl  → if a Codex runner script is pending, block until Claude runs it
#   Phase: done  → allow exit, clean up
#   All others   → allow exit (design phases are managed by commands, not this hook)
#
# Fail-open: on any error, approve exit to avoid trapping the user.
#
# Environment variables:
#   CLAUDEX_CODEX_FLAGS   Override codex flags (default: --dangerously-bypass-approvals-and-sandbox)
#   CLAUDEX_MAX_ROUNDS    Maximum Codex review rounds (default: 8)

LOG_FILE=".claudex.log"

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$LOG_FILE"
}

trap 'log "ERROR: hook exited via ERR trap (line $LINENO)"; rm -f .claudex-run-codex.sh .claudex-codex-prompt.txt; printf "{\"decision\":\"approve\"}\n"; exit 0' ERR

# Consume stdin (hook input JSON)
HOOK_INPUT=$(cat)

# Find active session file(s) via glob
SESSION_FILES=(.claudex-session-*.local.md)
# Filter to files that actually exist (glob may not expand)
ACTIVE_FILES=()
for f in "${SESSION_FILES[@]}"; do
  [ -f "$f" ] && ACTIVE_FILES+=("$f")
done

if [ "${#ACTIVE_FILES[@]}" -eq 0 ]; then
  printf '{"decision":"approve"}\n'
  exit 0
fi

# If multiple sessions exist, use the most recently modified one
if [ "${#ACTIVE_FILES[@]}" -gt 1 ]; then
  log "WARN: multiple session files found, using most recently modified"
  STATE_FILE=$(ls -t "${ACTIVE_FILES[@]}" | head -1)
else
  STATE_FILE="${ACTIVE_FILES[0]}"
fi

# Parse a field from the YAML frontmatter
parse_field() {
  sed -n "s/^${1}: *//p" "$STATE_FILE" | head -1
}

ACTIVE=$(parse_field "active")
PHASE=$(parse_field "phase")
SLUG=$(parse_field "slug")
TASK=$(parse_field "task")
ROUND=$(parse_field "round")
MAX_ROUNDS=$(parse_field "max_rounds")
MAX_ROUNDS="${MAX_ROUNDS:-8}"

# Validate slug to prevent path traversal
if ! echo "$SLUG" | grep -qE '^[a-z0-9][a-z0-9-]{0,47}$'; then
  log "ERROR: invalid slug format: $SLUG"
  rm -f "$STATE_FILE"
  printf '{"decision":"approve"}\n'
  exit 0
fi

# Not active → clean up and exit
if [ "$ACTIVE" != "true" ]; then
  rm -f "$STATE_FILE"
  printf '{"decision":"approve"}\n'
  exit 0
fi

case "$PHASE" in
  impl)
    # If a runner script is pending (written by /claudex:impl command), block and
    # tell Claude to execute it. The command itself orchestrates the loop; the hook
    # only intervenes if Claude tries to exit mid-loop without running the script.
    if [ -f ".claudex-run-codex.sh" ]; then
      REVIEW_ROUND_FILE="claudex/tasks/${SLUG}/review-impl-${ROUND}.md"
      log "Blocking exit: Codex runner script pending (round=$ROUND)"

      REASON="Codex review round ${ROUND} has not been completed yet.

Run the Codex review script (use a 600000ms timeout):
\`\`\`
bash .claudex-run-codex.sh \"${REVIEW_ROUND_FILE}\"
\`\`\`

Then read ${REVIEW_ROUND_FILE} and triage the findings before stopping."

      SYS_MSG="Claudex [${SLUG}] — impl round ${ROUND}: Codex review pending"

      jq -n --arg r "$REASON" --arg s "$SYS_MSG" \
        '{decision:"block", reason:$r, systemMessage:$s}' 2>/dev/null \
        || printf '{"decision":"block","reason":"Codex review pending. Run: bash .claudex-run-codex.sh"}\n'
    else
      # No pending runner — allow exit (loop is managed by the command)
      printf '{"decision":"approve"}\n'
    fi
    ;;

  done)
    # Session complete — clean up and allow exit
    log "Claudex session complete (slug=$SLUG)"
    rm -f "$STATE_FILE" .claudex-codex-prompt.txt .claudex-run-codex.sh
    printf '{"decision":"approve"}\n'
    ;;

  design|design-review)
    # Design phases are fully managed by commands — hook does not intervene
    printf '{"decision":"approve"}\n'
    ;;

  *)
    log "WARN: unknown phase '$PHASE', cleaning up"
    rm -f "$STATE_FILE" .claudex-codex-prompt.txt .claudex-run-codex.sh
    printf '{"decision":"approve"}\n'
    ;;
esac
