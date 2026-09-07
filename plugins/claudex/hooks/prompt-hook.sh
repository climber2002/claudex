#!/usr/bin/env bash
# Claudex — UserPromptSubmit Hook
#
# Fires on the first user message in a new session. If in-progress claudex
# sessions exist, injects a reminder so Claude surfaces them without being asked.
#
# Fail-open: any error produces an empty context injection (no-op).

trap 'printf "{}\n"; exit 0' ERR

# Consume stdin (hook input JSON)
HOOK_INPUT=$(cat)

# Only inject once per conversation — check if this is the first message
# by looking for a session marker. If it already exists, skip.
MARKER_FILE=".claudex-prompt-hook-fired.tmp"
if [ -f "$MARKER_FILE" ]; then
  printf '{}\n'
  exit 0
fi

# Find in-progress sessions
IN_PROGRESS=()
for f in .claudex-session-*.local.md; do
  [ -f "$f" ] || continue
  STATUS=$(sed -n 's/^status: *//p' "$f" | head -1)
  if [ "$STATUS" = "in_progress" ] || [ "$STATUS" = "not_started" ]; then
    TASK=$(sed -n 's/^task: *//p' "$f" | head -1)
    LAST=$(sed -n 's/^last_active: *//p' "$f" | head -1)
    SLUG=$(sed -n 's/^slug: *//p' "$f" | head -1)
    PHASE=$(sed -n 's/^phase: *//p' "$f" | head -1)
    IN_PROGRESS+=("${SLUG}|${TASK}|${PHASE}|${LAST}")
  fi
done

if [ "${#IN_PROGRESS[@]}" -eq 0 ]; then
  printf '{}\n'
  exit 0
fi

# Mark that we've fired this session so we don't inject on every message
touch "$MARKER_FILE"

# Build the injection message
MSG="Note: you have ${#IN_PROGRESS[@]} unfinished claudex session(s):"$'\n'
for entry in "${IN_PROGRESS[@]}"; do
  IFS='|' read -r slug task phase last <<< "$entry"
  MSG+="  • ${task} (phase: ${phase}, last active: ${last})"$'\n'
done
MSG+="Run \`/claudex:resume\` to continue one of these sessions."

jq -n --arg m "$MSG" '{context: $m}' 2>/dev/null || printf '{}\n'
