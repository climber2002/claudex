---
description: "Send the current plan doc to Codex for iterative review — loops until Codex says good to go"
allowed-tools:
  - Bash(bash .claudex-run-codex.sh *)
  - Bash(ls .claudex-session-*.local.md *)
  - Bash(cat .claudex-session-*.local.md)
  - Bash(awk * .claudex-session-*.local.md *)
  - Bash(mv .claudex-session-*.local.md.tmp .claudex-session-*.local.md)
  - Bash(rm -f .claudex-codex-prompt.txt .claudex-run-codex.sh)
  - Bash(mkdir -p claudex/tasks/*)
  - Read
  - Write
  - Edit
---

Find and read the session state:

```bash
ls .claudex-session-*.local.md 2>/dev/null
```

If no files found, report: "No active claudex session. Run `/claudex:begin-design` first."
If multiple files found, list them with their `task` field and ask the user which one to review.
Use the matching session file for all subsequent operations (referred to as `<session-file>` below).

```bash
cat <session-file>
```

Check that `phase` is `design`. If it's `impl`, report: "Session is already in impl phase."

Read the plan doc at `plan_path`. If it doesn't exist, report: "Plan doc not found at `<plan_path>`. Run `/claudex:begin-design` to generate it."

Transition the phase to `design-review` and update `last_active` (use awk rewrite, NOT sed):

```bash
awk -v ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{
  if ($0 ~ /^phase:/) { print "phase: design-review" }
  else if ($0 ~ /^last_active:/) { print "last_active: " ts }
  else { print }
}' <session-file> > <session-file>.tmp && mv <session-file>.tmp <session-file>
```

Now run the Codex design review loop.

For each round (starting at round 1, up to `max_rounds`):

1. Update `round` and `last_active` in the session file
2. Write the Codex prompt to `.claudex-codex-prompt.txt`:

```
Review this design plan for: <task>

<full contents of plan doc>

For each finding, specify whether it is a blocker or a suggestion.
Mention "good to go" if you accept the plan.
```

3. Write a runner script to `.claudex-run-codex.sh`:

```bash
#!/usr/bin/env bash
LOG_FILE=".claudex.log"
log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$LOG_FILE"; }
PROMPT_FILE=".claudex-codex-prompt.txt"
REVIEW_FILE="$1"
CODEX_FLAGS="${CLAUDEX_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox}"
if [ -n "${CLAUDEX_REASONING_EFFORT:-}" ]; then
  CODEX_FLAGS="$CODEX_FLAGS -c model_reasoning_effort=\"${CLAUDEX_REASONING_EFFORT}\""
fi
log "Starting Codex design review round"
codex $CODEX_FLAGS exec "$(cat "$PROMPT_FILE")" > "$REVIEW_FILE" 2>&1
log "Codex finished (exit=$?)"
```

4. Run Codex (use a 600000ms timeout):

```bash
bash .claudex-run-codex.sh "claudex/tasks/<slug>/review-design-<round>.md"
```

5. Read the review file. Present the findings to the user clearly.

6. Check if Codex output contains "good to go" (case-insensitive). If yes, break the loop.

7. If not good to go, triage each finding:
   - **Blocker**: update the plan doc to address it
   - **Suggestion**: evaluate soundness — if sound, update the plan; if unsound, note disagreement as a comment in the plan

8. Update `last_active` in the session file

9. Ask the user: "Round <N> complete. Findings addressed. Proceed to next Codex round? (or make further edits first)"

Wait for user confirmation before proceeding to the next round.

After the loop ends (either "good to go" or round cap hit):

- If "good to go": transition phase back to `design` and tell the user the plan is approved — run `/claudex:impl` when ready to implement
- If round cap hit: warn the user — "Max rounds reached without Codex approval. Review the plan manually before proceeding with `/claudex:impl`."

Update `last_active` in the session file.

Clean up: remove `.claudex-codex-prompt.txt` and `.claudex-run-codex.sh`
