# claudex

A Claude Code plugin that automates design and implementation workflows with iterative Codex review loops. Claude and Codex collaborate — Claude plans and implements, Codex reviews with prioritized findings, Claude triages, and the loop continues until Codex signs off.

Sessions are resumable across days and multiple Claude Code conversations.

Inspired by [hamelsmu/claude-review-loop](https://github.com/hamelsmu/claude-review-loop).

## What it does

Claudex introduces a three-phase workflow with human checkpoints between each phase:

1. **Design** — Claude generates a structured plan doc. You discuss and iterate with Claude directly.
2. **Design review** — Claude sends the plan to Codex in a loop until Codex says "good to go" (up to 8 rounds).
3. **Implementation** — Claude implements the plan. Codex reviews each commit, rates findings by priority (High / Medium / Low), and the loop continues until Codex accepts or the round cap is hit.

At the end, Claude prompts you to create a PR, merge, and/or clean up session files.

## Commands

| Command                       | Description                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------- |
| `/claudex-begin-design`       | Start a design session — Claude generates a plan doc for the given task      |
| `/claudex-review-design`      | Send the current plan to Codex for iterative review                          |
| `/claudex-impl`               | Implement the plan with a single Codex review loop over the full impl        |
| `/claudex-impl --per-subtask` | Implement with a separate Codex review loop per subtask                      |
| `/claudex-resume`             | Resume an in-progress session — shows all unfinished sessions, you pick one  |
| `/claudex-clean`              | Delete completed sessions and their task artifacts                           |
| `/claudex-cancel`             | Cancel the active session and clean up state                                 |

## Workflow

### 1. Design phase

```
/claudex-begin-design Add user authentication with JWT tokens
```

Claude generates `claudex/tasks/add-user-authentication-with-jwt-tokens/plan.md` with a structured breakdown including subtasks, architecture decisions, and open questions. Discuss and refine with Claude directly in the conversation.

### 2. Design review

```
/claudex-review-design
```

Claude sends the plan to Codex. Codex responds with findings (blockers or suggestions) or "good to go". Claude triages each finding and the loop repeats until Codex accepts the plan.

### 3. Implementation

```
/claudex-impl
```

or for larger tasks:

```
/claudex-impl --per-subtask
```

Claude implements the task. After each commit, Codex reviews with:

> Review commit `#<hash>` for `<task>`. Rate each finding High, Medium, or Low priority. Mention `good to go` if you accept this commit.

**Finding triage:**

| Priority     | What happens                                                                    |
| ------------ | ------------------------------------------------------------------------------- |
| High         | Claude must fix — blocking, no debate                                           |
| Medium / Low | Claude evaluates: sound → fix; unsound → challenge Codex next round            |
| Challenged & Codex stands firm | Deferred — saved for your review at the end        |

The loop exits when Codex says "good to go" or 8 rounds are reached.

### 4. End of session

When impl completes, Claude prompts:

```
What would you like to do next?
  1. Create a PR
  2. Merge to main
  3. Create a PR then clean up session files
  4. Merge to main then clean up session files
  5. Clean up session files now
  6. Do nothing (run /claudex-clean later)
```

## Resuming sessions

Sessions persist across Claude Code conversations. When you start a new conversation, Claudex automatically reminds you of any in-progress sessions.

To resume explicitly:

```
/claudex-resume
```

Shows all unfinished sessions with progress, last-active timestamp, and current subtask. You confirm before Claude continues.

## Session files

Each session creates `.claudex-session-<slug>.local.md` in your project root. Add it to `.gitignore` (Claudex does this for you in the project's gitignore template).

Session status:
- `not_started` — session created, impl not yet started
- `in_progress` — impl underway
- `done` — all subtasks complete and Codex accepted

## File structure (per task)

```
claudex/tasks/<slug>/
├── plan.md               # Design plan
├── subtasks.md           # Subtask checklist with status ([ ] / [~] / [x])
├── review-design-1.md    # Codex design review round 1
├── review-impl-1.md      # Codex impl review round 1
├── review-impl-2.md      # Codex impl review round 2
└── deferred.md           # Findings deferred after impl loops (if any)
```

## Plugin file structure

```
claudex/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── claudex-begin-design.md
│   ├── claudex-review-design.md
│   ├── claudex-impl.md
│   ├── claudex-resume.md
│   ├── claudex-clean.md
│   └── claudex-cancel.md
├── hooks/
│   ├── hooks.json
│   ├── stop-hook.sh        # Blocks exit if Codex runner is pending
│   └── prompt-hook.sh      # Injects in-progress session reminder on first message
├── scripts/
│   └── setup-claudex.sh
├── AGENTS.md               # Symlink to CLAUDE.md
├── CLAUDE.md
└── README.md
```

## Requirements

- [Claude Code](https://claude.ai/code) (CLI)
- [Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`
- `jq` — `brew install jq` (macOS) / `apt install jq` (Linux)
- `gh` — [GitHub CLI](https://cli.github.com/) (for PR creation / merge)

Codex multi-agent mode is required. Claudex enables it automatically in `~/.codex/config.toml` on first use.

## Installation

```bash
claude plugin marketplace add climber2002/claudex
claude plugin install claudex
```

## Configuration

| Variable             | Default                                      | Description                           |
| -------------------- | -------------------------------------------- | ------------------------------------- |
| `CLAUDEX_CODEX_FLAGS`| `--dangerously-bypass-approvals-and-sandbox` | Flags passed to the Codex CLI         |
| `CLAUDEX_MAX_ROUNDS` | `8`                                          | Maximum Codex review rounds per loop  |
