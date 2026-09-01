#!/usr/bin/env bash
set -euo pipefail

# Claudex — Setup Script
# Validates dependencies, checks for an existing session, and creates the state file.

ARGS=()
PHASE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --help|-h)
      cat << 'HELP'
Usage: /claudex-begin-design <task description>
       /claudex-impl [--per-subtask] <task description>

Environment variables:
  CLAUDEX_CODEX_FLAGS   Override codex flags (default: --dangerously-bypass-approvals-and-sandbox)
  CLAUDEX_MAX_ROUNDS    Maximum Codex review rounds per loop (default: 8)
HELP
      exit 0
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

TASK="${ARGS[*]:-}"

if [ -z "$TASK" ]; then
  echo "Error: No task description provided."
  exit 1
fi

if [ -z "$PHASE" ]; then
  echo "Error: --phase is required (design or impl)."
  exit 1
fi

# Check dependencies
if ! command -v codex &> /dev/null; then
  echo "Warning: 'codex' CLI not found. Install it to enable Codex reviews."
  echo "  npm install -g @openai/codex"
fi

if ! command -v jq &> /dev/null; then
  echo "Error: 'jq' is required but not found."
  echo "  macOS:  brew install jq"
  echo "  Linux:  apt install jq"
  exit 1
fi

# Derive slug from task description
SLUG=$(echo "$TASK" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-48)
if ! echo "$SLUG" | grep -qE '^[a-z0-9][a-z0-9-]{0,47}$'; then
  SLUG="task-$(date +%Y%m%d-%H%M%S)"
fi

STATE_FILE=".claudex-session-${SLUG}.local.md"

if [ -f "$STATE_FILE" ]; then
  echo "Error: A claudex session for '${SLUG}' is already active. Use /claudex-cancel to abort it first."
  exit 1
fi

MAX_ROUNDS="${CLAUDEX_MAX_ROUNDS:-8}"
PLAN_PATH="claudex/tasks/${SLUG}/plan.md"
SUBTASKS_PATH="claudex/tasks/${SLUG}/subtasks.md"

mkdir -p "claudex/tasks/${SLUG}"
mkdir -p .claude

cat > "$STATE_FILE" << STATE_EOF
---
active: true
status: not_started
phase: ${PHASE}
task: ${TASK}
slug: ${SLUG}
plan_path: ${PLAN_PATH}
subtasks_path: ${SUBTASKS_PATH}
round: 0
max_rounds: ${MAX_ROUNDS}
per_subtask: false
current_subtask: 0
total_subtasks: 0
started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_active: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---
STATE_EOF

# Create empty subtasks file
cat > "$SUBTASKS_PATH" << SUBTASKS_EOF
# Subtasks — ${TASK}

<!-- Populated by /claudex-impl when implementation begins -->
SUBTASKS_EOF

echo ""
echo "Claudex session started"
echo "  Task:     ${TASK}"
echo "  Slug:     ${SLUG}"
echo "  Phase:    ${PHASE}"
echo "  Plan:     ${PLAN_PATH}"
echo "  Subtasks: ${SUBTASKS_PATH}"
echo "  Session:  ${STATE_FILE}"
echo ""
echo "  Use /claudex-cancel to abort."
echo ""
