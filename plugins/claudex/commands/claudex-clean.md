---
description: "Delete completed claudex sessions — removes session files and task artifacts"
allowed-tools:
  - Bash(ls .claudex-session-*.local.md *)
  - Bash(cat .claudex-session-*.local.md)
  - Bash(rm -f .claudex-session-*.local.md)
  - Bash(rm -rf claudex/tasks/*)
  - Bash(rmdir claudex/tasks)
  - Bash(rmdir claudex)
  - Read
---

Find all session files:

```bash
ls .claudex-session-*.local.md 2>/dev/null
```

If no files found, report: "No claudex sessions found."

Read each session file and filter to those where `status` is `done`. Extract `task`, `slug`, `last_active` from each.

If no done sessions found, report: "No completed claudex sessions to clean. Run `/claudex-resume` to see active sessions."

Print a numbered list of completed sessions:

```
Completed claudex sessions:

  1. <slug>
     Task:        <task>
     Last active: <last_active>
     Will delete: .claudex-session-<slug>.local.md
                  claudex/tasks/<slug>/

  2. ...

Which sessions would you like to delete?
  Enter a number, comma-separated numbers, or "all" (or "cancel" to abort)
```

Wait for user input.

For each selected session:

1. Confirm what will be deleted:
   ```
   Deleting session: <task>
     .claudex-session-<slug>.local.md
     claudex/tasks/<slug>/  (<N> files)
   ```

2. Delete the session file and task directory:
   ```bash
   rm -f .claudex-session-<slug>.local.md
   rm -rf claudex/tasks/<slug>/
   ```

After all deletions, report: "Cleaned <N> session(s)."

If the `claudex/tasks/` directory is now empty, offer to remove it:
```bash
rmdir claudex/tasks 2>/dev/null && rmdir claudex 2>/dev/null || true
```
