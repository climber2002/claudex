---
description: "Resume an in-progress claudex session — shows all unfinished sessions and lets you pick one"
allowed-tools:
  - Bash
  - Read
---

Find all session files:

```bash
ls .claudex-session-*.local.md 2>/dev/null
```

If no files found, report: "No claudex sessions found. Start one with `/claudex-begin-design`."

Read each session file and filter to those where `status` is not `done`. For each, extract: `task`, `phase`, `status`, `current_subtask`, `total_subtasks`, `last_active`, `slug`.

If no unfinished sessions found, report: "No active claudex sessions. All sessions are complete. Use `/claudex-clean` to remove finished sessions."

Print a numbered summary of unfinished sessions:

```
Active claudex sessions:

  1. <slug>
     Task:        <task>
     Phase:       <phase>
     Status:      <status>
     Progress:    subtask <current_subtask> / <total_subtasks>  (if in_progress and per_subtask)
     Last active: <last_active>

  2. ...

Which session would you like to resume? (enter number or "cancel")
```

Wait for user input.

On selection, read the chosen session file fully. Also read:
- The plan doc at `plan_path`
- The subtasks file at `subtasks_path`
- The last Codex review file, if any (latest `claudex/tasks/<slug>/review-impl-*.md` or `review-design-*.md`)

Print a detailed resume summary:

```
Resuming: <task>
Last active: <last_active>
Phase: <phase>

Plan: <plan_path>

Subtask progress:
  ✓  1. <subtask> (done)
  ✓  2. <subtask> (done)
  →  3. <subtask> (in progress, round <round> / <max_rounds>)
     4. <subtask> (not started)
     5. <subtask> (not started)

Last Codex review: <review file path>  (if exists)
```

Ask: "Ready to resume? (yes / cancel)"

If yes:
- Update `last_active` in the session file
- Continue from where the session left off:
  - Phase `design`: re-open the plan doc and remind the user where the discussion was
  - Phase `design-review`: ask "Re-run Codex design review, or go back to editing the plan?"
  - Phase `impl`: continue the impl loop from `current_subtask` at the current `round` — follow the resume detection flow in `/claudex-impl`
