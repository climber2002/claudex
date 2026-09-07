---
description: "Implement the plan with an iterative Codex review loop — use --per-subtask for a separate loop per subtask"
argument-hint: "[--per-subtask] <task description>"
allowed-tools:
  - Bash(bash .claudex-run-codex.sh *)
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-claudex.sh" *)
  - Bash(git rev-parse --short HEAD)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(ls .claudex-session-*.local.md *)
  - Bash(cat .claudex-session-*.local.md)
  - Bash(awk * .claudex-session-*.local.md * )
  - Bash(mv .claudex-session-*.local.md.tmp .claudex-session-*.local.md)
  - Bash(rm -f .claudex-codex-prompt.txt .claudex-run-codex.sh)
  - Bash(mkdir -p claudex/tasks/*)
  - Read
  - Write
  - Edit
---

Parse arguments:
- Check if `--per-subtask` is present in `$ARGUMENTS`
- The remaining text after removing `--per-subtask` is the task description

Derive the slug from the task description (lowercase, spaces → hyphens, strip special chars, truncate at 48 chars).

## Session resolution

Check if a session already exists for this slug:

```bash
ls .claudex-session-<slug>.local.md 2>/dev/null
```

**If the session file exists** — read it and continue to Resume detection below.

**If no session file exists** — this is a new impl without a prior design phase. Run the setup script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-claudex.sh" --phase impl "<task description>"
```


Then generate a plan doc at `claudex/tasks/<slug>/plan.md` using the current conversation context:
- Summarize what was discussed as the Overview
- Extract concrete subtasks with acceptance criteria from the discussion
- Note any architecture decisions or constraints mentioned
- Leave Open questions blank if none were raised

Tell the user: "Generated plan from our discussion at `claudex/tasks/<slug>/plan.md`. Review it and confirm, or say 'looks good' to proceed."

Wait for confirmation before continuing.

**If multiple session files exist for different slugs** — list them with their `task` and `status` fields and ask the user which one to implement.

Use the session file for all subsequent operations (referred to as `<session-file>` below).

```bash
cat <session-file>
```

## Resume detection

If `status` is `in_progress`, this is a resumed session. Read the subtasks file at `subtasks_path` to reconstruct state. Print a resume summary:

```
Resuming claudex session: <task>
Last active: <last_active>
Phase: <phase>
Progress:
  Subtask 1: Add JWT middleware ✓ done
  Subtask 2: Add login endpoint ✓ done
  Subtask 3: Add refresh token logic  ← current (round 2 / 8)
  Subtask 4: Add logout endpoint  not started
  Subtask 5: Write tests  not started

Last Codex review: claudex/tasks/<slug>/review-impl-<round>.md
```

Ask: "Resume from subtask 3, round 2? (yes / start subtask over / cancel)"

Wait for user confirmation before proceeding.

---

## Setup

If `per_subtask` flag is set, update the state file:

```bash
awk '{if ($0 ~ /^per_subtask:/) { print "per_subtask: true" } else { print }}' \
  <session-file> > <session-file>.tmp && mv <session-file>.tmp <session-file>
```

Transition `phase` to `impl` and `status` to `in_progress`, update `last_active`:

```bash
awk -v ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{
  if ($0 ~ /^phase:/) { print "phase: impl" }
  else if ($0 ~ /^status:/) { print "status: in_progress" }
  else if ($0 ~ /^last_active:/) { print "last_active: " ts }
  else { print }
}' <session-file> > <session-file>.tmp && mv <session-file>.tmp <session-file>
```

Read the plan doc at `plan_path`. Extract the list of subtasks.

Populate `subtasks_path` with the full subtask list (mark previously completed ones as done if resuming):

```markdown
# Subtasks — <task>

- [ ] Subtask 1 title
- [ ] Subtask 2 title
- [ ] Subtask 3 title
```

Update `total_subtasks` in the session file to the count of subtasks.

---

## Without `--per-subtask` (single loop)

Implement the full task according to the plan. Commit all changes when done.

Mark all subtasks as done in `subtasks_path`.

Then run the **Impl Review Loop** (see below) over the full set of commits.

---

## With `--per-subtask`

For each subtask (skipping already-done ones when resuming):

1. Update `current_subtask` in the session file to the subtask index
2. Update `last_active` in the session file
3. Mark the subtask as in-progress in `subtasks_path`: `- [~] Subtask title`
4. Implement the subtask
5. Commit with a clear message referencing the subtask
6. Run the **Impl Review Loop** (see below) for that subtask's commit
7. After the loop exits, mark the subtask as done in `subtasks_path`: `- [x] Subtask title`
8. Update `last_active` in the session file
9. Only proceed to the next subtask after the loop exits successfully

---

## Impl Review Loop

This loop runs after each commit (or after the full impl in single-loop mode).

Accumulated deferred findings for this loop are tracked in memory across rounds.

For each round (starting at 1, up to `max_rounds`):

1. Get the latest commit hash:
```bash
git rev-parse --short HEAD
```

2. Update `round` and `last_active` in the session file

3. Build the Codex prompt. On round 1:

```
Review commit #<hash> for: <task>

Rate each finding High, Medium, or Low priority.
- High priority findings must be fixed before this can be accepted.
- Medium and Low priority findings are suggestions.

Mention "good to go" if you accept this commit.
```

On subsequent rounds, prepend any outstanding challenges from the previous round:

```
In the previous review you flagged the following findings. I have addressed the High priority items.
For the items below, I disagree and ask you to reconsider:

- "<finding A>": <Claude's reasoning for disagreement>
- "<finding B>": <Claude's reasoning for disagreement>

Please review commit #<hash> again and either revise these findings or confirm you stand by them.
Rate any new findings High, Medium, or Low priority.
Mention "good to go" if you accept this commit.
```

4. Write prompt to `.claudex-codex-prompt.txt` and runner to `.claudex-run-codex.sh`:

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
log "Starting Codex impl review round"
codex $CODEX_FLAGS exec "$(cat "$PROMPT_FILE")" > "$REVIEW_FILE" 2>&1
log "Codex finished (exit=$?)"
```

5. Run Codex (use a 600000ms timeout):

```bash
bash .claudex-run-codex.sh "claudex/tasks/<slug>/review-impl-<round>.md"
```

6. Read the review file. Present findings to the user grouped by priority.

7. Check if Codex output contains "good to go" (case-insensitive). If yes, break the loop.

8. Triage and fix findings **without asking the user**:

   - **High priority**: fix immediately and commit — no debate, no confirmation needed
   - **Medium / Low priority**: evaluate soundness autonomously
     - If **sound**: implement the fix and commit
     - If **unsound**: add to the challenges list for the next round's prompt — do NOT ask the user
     - If Codex **stands firm** on a challenged finding (same finding reappears after challenge): mark as deferred silently

9. After all findings are triaged and fixed, present a round summary to the user:
   - Fixed findings (with commit hash)
   - Findings you challenged (will be re-reviewed next round)
   - Deferred findings so far

10. Ask: "Round <N> complete. Proceed to next Codex round? (yes / stop)"

Wait for user confirmation before running the next Codex round. This is the **only** point where user input is required mid-loop.

---

## After each loop exits

If any deferred findings exist, append them to `claudex/tasks/<slug>/deferred.md`:

```markdown
# Deferred Findings — <task> [Subtask: <subtask title>]

## <Finding description>
- **Priority**: Medium / Low
- **Codex finding**: <original finding text>
- **Claude's challenge**: <reasoning>
- **Codex response**: <Codex's reply when challenged>

---
```

---

## After all subtasks are done (or single loop complete)

Mark `status` as `done` and `phase` as `done` in the session file. Update `last_active`.

Print completion summary:

```
=== Claudex Session Complete ===
Task:     <task>
Subtasks: <N> completed
Rounds:   <total rounds across all subtasks>
Fixed:    <count> findings
Deferred: <count> findings

Deferred findings: claudex/tasks/<slug>/deferred.md (if any)
```

Then prompt the user with next steps:

```
What would you like to do next?
  1. Create a PR
  2. Merge to main
  3. Create a PR then clean up session files
  4. Merge to main then clean up session files
  5. Clean up session files now
  6. Do nothing (run /claudex:clean later)
```

For options 1 / 3: create a PR using `gh pr create`, using the task description and plan doc as the PR body context.
For options 2 / 4: merge to main (`gh pr merge` or `git merge` as appropriate).
For options 3 / 4 / 5: delete `<session-file>` and `claudex/tasks/<slug>/` directory.

Clean up `.claudex-codex-prompt.txt` and `.claudex-run-codex.sh` in all cases.
