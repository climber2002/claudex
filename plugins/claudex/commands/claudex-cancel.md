---
description: "Cancel the active claudex session and clean up all state"
allowed-tools:
  - Bash(ls .claudex-session-*.local.md *)
  - Bash(cat .claudex-session-*.local.md)
  - Bash(rm -f .claudex-session-*.local.md .claudex-codex-prompt.txt .claudex-run-codex.sh .claudex.log)
  - Read
---

Find active session files:

```bash
ls .claudex-session-*.local.md 2>/dev/null
```

If no files found, report: "No active claudex session found."

If multiple files found, list them with their `task` and `phase` fields and ask the user which one to cancel (or "all").

For each session to cancel, read it to get `phase` and `task`, then remove it and its temp files:

```bash
rm -f <session-file> \
      .claudex-codex-prompt.txt \
      .claudex-run-codex.sh \
      .claudex.log
```

Report: "Claudex session cancelled (task: <task>, phase: <phase>)" for each cancelled session.
