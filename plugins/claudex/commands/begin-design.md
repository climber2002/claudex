---
description: "Start a design session — Claude generates a structured plan doc for the given task"
argument-hint: "<task description>"
allowed-tools:
  - Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-claudex.sh" *)
  - Bash(ls .claudex-session-*.local.md *)
  - Bash(cat .claudex-session-*.local.md)
  - Bash(awk * .claudex-session-*.local.md *)
  - Bash(mv .claudex-session-*.local.md.tmp .claudex-session-*.local.md)
  - Bash(mkdir -p claudex/tasks/*)
  - Read
  - Write
  - Edit
---

First, run the setup script to initialize the session:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-claudex.sh" --phase design "$ARGUMENTS"
```

If setup fails, stop and report the error to the user.

After setup, read the session file (it will be `.claudex-session-<slug>.local.md`) to get the `plan_path`, `subtasks_path`, and `task` fields.

Then generate a plan doc at the `plan_path` location. The plan should include:

1. **Overview** — one paragraph summarizing the task and its goals
2. **Subtasks** — a numbered list of concrete subtasks with clear acceptance criteria for each
3. **Architecture / design decisions** — key choices, trade-offs, and rationale
4. **Out of scope** — anything explicitly not being done in this task
5. **Open questions** — anything that needs clarification before implementation begins

Write the plan to the `plan_path` file.

Update `last_active` in the session file to the current UTC timestamp:

```bash
awk '{if ($0 ~ /^last_active:/) { print "last_active: '"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'" } else { print }}' \
  <session-file> > <session-file>.tmp && mv <session-file>.tmp <session-file>
```

Then tell the user:

- The plan has been written to `<plan_path>`
- They can discuss and iterate on the plan directly in this conversation
- When the plan is ready for Codex review, run `/claudex:review-design`
- To cancel and start over, run `/claudex:cancel`
