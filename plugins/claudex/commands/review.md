---
description: "Run a Codex review on a target (diff, commit, file, or free-form context) — optionally loop until all findings at a given priority level are resolved. Triggered by natural language: 'use claudex to review', 'codex review', 'claudex review until all medium findings are resolved', etc."
allowed-tools:
  - Bash(bash .claudex-run-codex.sh *)
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(git rev-parse --short *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(rm -f .claudex-codex-prompt.txt .claudex-run-codex.sh)
  - Read
  - Write
  - Edit
---

## Argument extraction

From the user's natural language request, extract:

**Target** — what to review (default: uncommitted changes):
- "current diff" / "uncommitted changes" / nothing specified → `git diff`
- "last commit" / "latest commit" / "HEAD" → `git diff HEAD~1..HEAD`
- A git ref or range (e.g. `abc123`, `HEAD~3..HEAD`) → `git diff <range>`
- A file path or glob → read those files as context
- Free-form description (e.g. "the auth logic") → append as context in the Codex prompt

**Threshold** — when to stop looping (default: none — one-shot):
- "until all high findings are resolved" / "until no high findings" → `high`
- "until all medium findings are resolved" / "until medium" → `medium`
- "until all low findings are resolved" / "until everything is clean" → `low`
- No threshold mentioned → one-shot (run once, show findings, done)

---

## Build the review context

Gather the content to review based on the target:

```bash
# For uncommitted changes:
git diff

# For a commit range:
git diff <range>

# For a file:
# Read the file directly
```

If the diff/content is empty, report: "Nothing to review — no changes found for the specified target." and stop.

Get the current commit hash for reference:
```bash
git rev-parse --short HEAD
```

---

## One-shot mode (no threshold)

Build the Codex prompt:

```
Review the following for: <user's description or "current changes">

<diff or file contents>

Rate each finding High, Medium, or Low priority.
- High: must be fixed before this can be accepted
- Medium / Low: suggestions

Mention "good to go" if you have no findings.
```

Write prompt to `.claudex-codex-prompt.txt` and runner to `.claudex-run-codex.sh`:

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
log "Starting Codex review (one-shot)"
codex $CODEX_FLAGS exec "$(cat "$PROMPT_FILE")" > "$REVIEW_FILE" 2>&1
log "Codex finished (exit=$?)"
```

Run Codex (use a 600000ms timeout):

```bash
bash .claudex-run-codex.sh ".claudex-review-output.tmp"
```

Read `.claudex-review-output.tmp` and present findings grouped by priority. Then offer:

```
Save findings to a file? (yes / no)
```

If yes, ask for a filename (default: `claudex-review.md`) and write the findings there.

Clean up: `rm -f .claudex-codex-prompt.txt .claudex-run-codex.sh .claudex-review-output.tmp`

---

## Loop mode (threshold specified)

Threshold levels:
- `high` → loop exits when no High findings remain
- `medium` → loop exits when no High or Medium findings remain
- `low` → loop exits when Codex has no findings at all (or says "good to go")

Track accumulated deferred findings in memory across rounds.

For each round (starting at 1):

1. Build the Codex prompt. On round 1:

```
Review the following for: <user's description or "current changes">

<diff of current uncommitted changes, or original target if file/range>

Rate each finding High, Medium, or Low priority.
- High: must be fixed before this can be accepted
- Medium / Low: suggestions

Mention "good to go" if you have no findings.
```

On subsequent rounds, include any outstanding challenges from the previous round:

```
In the previous review you flagged the following findings. I have addressed the findings at or above the threshold.
For the items below, I disagree and ask you to reconsider:

- "<finding A>": <reasoning>
- "<finding B>": <reasoning>

Please review the current state again and either revise these findings or confirm you stand by them.
Rate any new findings High, Medium, or Low priority.
Mention "good to go" if you have no findings at or above <threshold> priority.
```

2. Write prompt to `.claudex-codex-prompt.txt` and runner to `.claudex-run-codex.sh`:

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
log "Starting Codex review round"
codex $CODEX_FLAGS exec "$(cat "$PROMPT_FILE")" > "$REVIEW_FILE" 2>&1
log "Codex finished (exit=$?)"
```

3. Run Codex (use a 600000ms timeout):

```bash
bash .claudex-run-codex.sh ".claudex-review-output.tmp"
```

4. Read `.claudex-review-output.tmp`. Present findings to the user grouped by priority.

5. Check exit condition:
   - If Codex output contains "good to go" (case-insensitive) → exit loop
   - If threshold is `high` and no High findings remain → exit loop
   - If threshold is `medium` and no High or Medium findings remain → exit loop
   - If threshold is `low` and no findings remain → exit loop

6. Triage and fix findings **without asking the user**:

   - Findings **at or above the threshold**: fix immediately and commit — no debate
   - Findings **below the threshold**: evaluate soundness
     - Sound → fix and commit
     - Unsound → add to challenges list for next round — do NOT ask the user
     - Codex stands firm after challenge → mark as deferred silently

7. After all fixes are committed, present a round summary:
   - Fixed findings (with commit hash)
   - Challenged findings (will be re-reviewed next round)
   - Deferred findings so far

8. Ask: "Round <N> complete. Proceed to next Codex round? (yes / stop)"

   Wait for user confirmation before the next round.

---

## After the loop exits

Print a summary:

```
=== Claudex Review Complete ===
Target:    <target description>
Threshold: <high / medium / low>
Rounds:    <N>
Fixed:     <count> findings
Deferred:  <count> findings
```

If any deferred findings exist, print them.

Offer:

```
Save findings to a file? (yes / no)
```

If yes, ask for a filename (default: `claudex-review.md`) and write the full findings (all rounds) there.

Clean up: `rm -f .claudex-codex-prompt.txt .claudex-run-codex.sh .claudex-review-output.tmp`
