# Claudex — Agent Guidelines

## What this is

A Claude Code plugin implementing a three-phase design-and-implementation workflow with iterative Codex review loops:

1. `/claudex-begin-design` — Claude generates a plan doc, user iterates with Claude
2. `/claudex-review-design` — Claude sends plan to Codex, loops until "good to go"
3. `/claudex-impl [--per-subtask]` — Claude implements, Codex reviews each commit with priority-rated findings, loops until "good to go"
4. `/claudex-resume` — resume an in-progress session in a new Claude conversation
5. `/claudex-clean` — delete completed sessions and their task artifacts
6. `/claudex-cancel` — cancel and clean up an active session

## Session state

Each session has its own state file: `.claudex-session-<slug>.local.md` (gitignored).

### Frontmatter fields

| Field             | Values                                         | Description                              |
| ----------------- | ---------------------------------------------- | ---------------------------------------- |
| `active`          | `true` / `false`                               | Whether the session is active            |
| `status`          | `not_started` / `in_progress` / `done`         | Overall task status                      |
| `phase`           | `design` / `design-review` / `impl` / `done`   | Current workflow phase                   |
| `task`            | string                                         | Full task description                    |
| `slug`            | kebab-case string, max 48 chars                | Derived from task, used in file paths    |
| `plan_path`       | path                                           | `claudex/tasks/<slug>/plan.md`           |
| `subtasks_path`   | path                                           | `claudex/tasks/<slug>/subtasks.md`       |
| `round`           | integer                                        | Current Codex review round               |
| `max_rounds`      | integer (default 8)                            | Maximum rounds per loop                  |
| `per_subtask`     | `true` / `false`                               | Whether impl runs a loop per subtask     |
| `current_subtask` | integer                                        | Current subtask index (1-based)          |
| `total_subtasks`  | integer                                        | Total number of subtasks                 |
| `started_at`      | ISO 8601 UTC                                   | Session creation time                    |
| `last_active`     | ISO 8601 UTC                                   | Updated on every meaningful state change |

### Subtasks file (`claudex/tasks/<slug>/subtasks.md`)

Tracks per-subtask status using GitHub-style checkboxes:
- `- [ ]` — not started
- `- [~]` — in progress
- `- [x]` — done

### Status transitions

```
not_started → in_progress  (when /claudex-impl begins)
in_progress → done         (when all subtasks complete and Codex says "good to go")
```

### Phase transitions

```
design → design-review  (when /claudex-review-design starts)
design-review → design  (when design review loop exits)
design → impl           (when /claudex-impl starts)
impl → done             (when all impl loops complete)
```

## File layout

```
claudex/
├── tasks/
│   └── <slug>/
│       ├── plan.md               # Design plan
│       ├── subtasks.md           # Subtask checklist with status
│       ├── review-design-<N>.md  # Codex design review round N
│       ├── review-impl-<N>.md    # Codex impl review round N
│       └── deferred.md           # Deferred findings after impl loops
.claudex-session-<slug>.local.md  # Session state (gitignored)
.claudex-codex-prompt.txt         # Temp: current Codex prompt (gitignored)
.claudex-run-codex.sh             # Temp: Codex runner script (gitignored)
.claudex.log                      # Telemetry log (gitignored)
.claudex-prompt-hook-fired.tmp    # Prevents repeated prompt hook injection (gitignored)
```

## Conventions

- Shell scripts must work on both macOS and Linux (handle `sed -i ''` vs `sed -i` differences)
- The stop hook MUST always produce valid JSON to stdout — never let non-JSON text leak
- Fail-open: on any error, approve exit rather than trapping the user
- Phase transitions must rewrite the state file atomically (awk rewrite, NOT sed regex), then verify before proceeding
- All `jq` calls that produce block decisions MUST have a `|| printf '...'` fallback
- Codex runs via a runner script (`.claudex-run-codex.sh`) that Claude executes via Bash — output streams to the user
- Codex prompt is saved to `.claudex-codex-prompt.txt` before each round
- Telemetry goes to `.claudex.log` — structured, timestamped lines
- Update `last_active` on every meaningful state change
- Claude Code does NOT set `stop_hook_active` in hook input — do not rely on it for re-entrancy detection

## Task slugs

- Derived from the task description: lowercase, spaces → hyphens, strip special chars, truncate at 48 chars
- Validate against `^[a-z0-9][a-z0-9-]{0,47}$` before using in paths
- Used in session filename, task directory, and all artifact paths

## Codex prompt formats

**Design review:**
```
Review this design plan for: <task>

<plan contents>

For each finding, specify whether it is a blocker or a suggestion.
Mention "good to go" if you accept the plan.
```

**Impl review (round 1):**
```
Review commit #<hash> for: <task>

Rate each finding High, Medium, or Low priority.
- High priority findings must be fixed before this can be accepted.
- Medium and Low priority findings are suggestions.

Mention "good to go" if you accept this commit.
```

**Impl review (subsequent rounds with challenges):**
```
In the previous review you flagged the following findings. I have addressed the High priority items.
For the items below, I disagree and ask you to reconsider:

- "<finding>": <Claude's reasoning>

Please review commit #<hash> again and either revise these findings or confirm you stand by them.
Rate any new findings High, Medium, or Low priority.
Mention "good to go" if you accept this commit.
```

## Finding triage (impl phase)

- **High**: Claude must address — blocking, no debate
- **Medium / Low**: Claude evaluates soundness
  - Sound → implement
  - Unsound → challenge in next round's prompt
  - Codex stands firm after challenge → mark as deferred

## Loop termination

- Exit when Codex output contains "good to go" (case-insensitive)
- Exit when `round >= max_rounds` — print warning, proceed anyway
- On exit: write deferred findings to `deferred.md` and print summary

## End-of-session prompt

When all subtasks are done, prompt user:
```
What would you like to do next?
  1. Create a PR
  2. Merge to main
  3. Create a PR then clean up session files
  4. Merge to main then clean up session files
  5. Clean up session files now
  6. Do nothing (run /claudex-clean later)
```

For PR creation: use `gh pr create` with the task description and plan doc as context.
For cleanup: delete `<session-file>` and `claudex/tasks/<slug>/`.

## Security constraints

- Task slugs are validated to prevent path traversal
- No secrets or credentials stored in state files
- Codex flags configurable via `CLAUDEX_CODEX_FLAGS` — never hardcode

## Testing checklist

After modifying stop-hook.sh:
- [ ] No-state path: approves exit cleanly
- [ ] `design` / `design-review` phases: approves exit (hook does not intervene)
- [ ] `impl` phase, runner pending: blocks with instructions
- [ ] `impl` phase, no runner pending: approves exit
- [ ] `done` phase: approves exit, cleans up
- [ ] Malformed state: fails open
- [ ] Multiple session files: uses most recently modified
- [ ] All JSON output passes `jq .`

After modifying prompt-hook.sh:
- [ ] No sessions: returns `{}`
- [ ] In-progress sessions: injects context message
- [ ] Only done sessions: returns `{}`
- [ ] Fires only once per conversation (marker file check)
- [ ] Any error: returns `{}` (fail-open)
