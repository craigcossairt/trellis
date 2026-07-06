# AGENTS.md — <!-- FILL IN: Project Name -->

> Canonical instructions for AI coding agents (Claude Code, Cursor, Codex, Gemini CLI, and others).
> Keep this file **harness-agnostic**: anything specific to one tool belongs in that tool's own
> config directory (`.claude/`, `.cursor/`, etc.). CLAUDE.md imports this file, so never duplicate
> content between the two.

## Project

- **Name:** <!-- FILL IN -->
- **What it is:** <!-- FILL IN: one-line description -->
- **Owner:** <!-- FILL IN: name — email -->
- **Stage:** <!-- FILL IN: idea / prototype / MVP / production -->
- For the owner's background and working style, see `docs/about-me.md`

## What I Need From Agents

- Research before advising — verify current facts (pricing, APIs, legal) before recommending
- When writing code, explain what you're doing and why in plain language
- If uncertain, say so explicitly — never fabricate facts or statistics
- Skip long preambles — get to the point
- Flag when professional review is needed (lawyer, accountant, security auditor)
- Default to actionable advice that can be executed this week

## Current State — Source of Truth Pointers

**This file does NOT own current priorities, active deadlines, or in-progress work.** Those change
too fast for a static config file. Read the live sources below before acting on anything that
depends on what's currently active or due:

- **Active issues + priorities** — <!-- FILL IN: issue tracker URL (Linear, GitHub Issues, ...) -->
- **Decision history (what was decided, when, why)** — `docs/decision-log.md`
- **Known bug patterns** — `docs/common-gotchas.md`

**What this file owns:** stable conventions (tech stack, methodology, file structure, owner
context). The test for whether something belongs here: *"Will this still be true in 6 months?"*
If no, it goes in the issue tracker, not here.

## Tech Stack

<!-- FILL IN: delete rows that don't apply, add your own -->

| Layer | Technology |
|---|---|
| Frontend | |
| Backend | |
| Database | |
| Hosting | |
| Issue Tracking | |
| Error Tracking | |

## Getting Started

<!-- FILL IN: the commands a fresh clone needs to run -->

```bash
# install deps:
# run dev server:
# run tests:
# lint / typecheck:
```

## Folder Structure

<!-- FILL IN once the project takes shape. Keep this a map, not an inventory. -->

```
.
├── docs/
│   ├── common-gotchas.md    # symptom → root cause → fix table (append after every bug fix)
│   ├── decision-log.md      # one line per decision
│   └── methodology/         # TDD workflow, bug protocol, session habits
├── .claude/                 # Claude Code adapter (hooks, commands, skills, agents)
├── .cursor/                 # Cursor adapter
└── brain/                   # optional local knowledge base (see brain/README.md)
```

If this project outgrows a single repo (second repo, non-code assets piling up), see
`docs/growing-into-a-workspace.md` for the graduation path.

## Rules

### Working Methodology

- **Plan first for non-trivial tasks** (3+ steps or architectural decisions) — write the plan,
  confirm before implementing. If something goes wrong mid-implementation, STOP and re-plan.
- **Verify before marking done** — never claim a task is complete without proving it works. Run
  tests, check logs, demonstrate correctness. Ask: "Would a staff engineer approve this?"
- **Autonomous bug fixing** — when given a bug report, follow `docs/methodology/bug-protocol.md`
  automatically. If details are missing, ask for them.
- **TDD by default** — for code work, follow `docs/methodology/tdd.md`. Write failing tests first,
  then implement.
- **Simplicity first** — make every change as simple as possible. Minimize code impact. No
  temporary fixes — find root causes.

### AI Session Management

Context quality degrades in long sessions. Defaults for every session:

- **Prefer rewinding over mid-session correction.** When an approach flops after exploration, jump
  back to just after the research and re-prompt with what you learned, rather than stacking
  corrections on a bad chain.
- **New task = new session.** Pivoting to unrelated work means a fresh session, not a continue.
  Exception: closely related follow-ons (docs for the feature just shipped).
- **Compact with direction.** When a long session approaches its context limit, summarize with an
  explicit instruction about what to keep and what to drop.
- **Delegate big-output work to subagents.** Exhaustive searches, security review passes, bulk
  scans — route through a subagent so only the conclusion hits the main context. Mental test:
  "Do I need the tool output or just the conclusion?"
- **Summarize before ending.** When closing a session mid-stream, write a handoff summary for the
  next session.

### Delegation & Model Routing

For most tasks the right team size is 1 (yourself) or 2 (you + one reviewer agent). When you do
delegate:

- **Push work down, keep judgment up.** Spend the parent context on decisions, synthesis, and
  review; let subagents burn their own context on searches, file dumps, and mechanical edits.
- **Brief every child completely.** A subagent starts blank. Every dispatch includes the context
  (files, constraints, conventions), the why, and what done looks like. Include an explicit
  "do not delete files" clause for file-writing subagents.
- **Return work above your tier.** If a dispatched agent hits a problem harder than its tier
  (architecture call, security judgment, ambiguous requirement), it should return findings and
  stop — not grind tokens on it.
- **Don't delegate the trivial.** Single-fact lookups, one-file edits, anything faster to do than
  to brief — do it yourself.

| Tier | Best for | Delegate to it when |
|---|---|---|
| Fast <!-- FILL IN: current model --> | Bulk mechanical work: exhaustive greps, file inventories, formatting | Output is large, judgment is minimal, correctness is cheap to verify |
| Mid <!-- FILL IN --> | Routine implementation following an established pattern | The pattern exists in the repo and a review pass will catch mistakes |
| Strong <!-- FILL IN --> | Complex implementation, debugging, refactors, code review | The task needs real reasoning within known constraints |
| Frontier <!-- FILL IN --> | Architecture decisions, auth/security design, ambiguous tradeoffs | One-shot hard calls; the escalation target |

Refresh the model names when the model family turns over; the tier structure is the stable part.

### Content Rules

- Never fabricate statistics or market data — search first
- All externally-facing content must be original — no copying from competitors
- <!-- OPTIONAL, keep or delete: --> No em dashes (—) in externally-facing content (marketing
  copy, user-facing UI text, emails to outside parties, public posts). Use hyphens, commas,
  parentheses, or separate sentences. Em dashes are fine in internal docs, code comments, and
  commit messages.

### Autonomous Housekeeping (do these WITHOUT being asked)

**After every bug fix:**
- Append the symptom / root cause / fix to `docs/common-gotchas.md`.

**After every completed task (feature, bug fix, refactor):**
- Commit the changes with a descriptive message. Stage only the relevant files (never .env,
  secrets, or lock files unless intentional).
- Push to the remote branch. If on a feature branch, offer to create a PR.

**After making or discovering a project decision:**
- Append a one-line entry to `docs/decision-log.md`
  (format: `- **YYYY-MM-DD** — Decision description. See <issue-ref>.`)

**After fixing a recurring issue or learning a new codebase pattern:**
- Update this file if it's a convention agents need every session
- Update `docs/common-gotchas.md` if it's a symptom-to-fix pattern

**When context files get stale:**
- If this file drifts on stable conventions, flag it and suggest updates
- If the issue tracker is out of date based on something that just happened, flag it — do not
  change tracker priorities or close issues autonomously without permission

## Formatting Preferences

- Use bullet points for action items
- Use Markdown: sections, tables, numbered lists where appropriate
- When writing externally-facing content, align with the brand voice
  (<!-- FILL IN: link brand/voice doc when one exists -->)
- When writing internal/working docs, prioritize clarity and speed
