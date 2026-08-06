# AGENTS.md - <!-- FILL IN: Project Name -->

> Canonical instructions for AI coding agents (Claude Code, Cursor, Codex, Gemini CLI, and others).
> Keep this file **harness-agnostic**: anything specific to one tool belongs in that tool's own
> config directory (`.claude/`, `.cursor/`, etc.). CLAUDE.md imports this file, so never duplicate
> content between the two.

## Project

- **Name:** <!-- FILL IN -->
- **What it is:** <!-- FILL IN: one-line description -->
- **Owner:** <!-- FILL IN: name - email -->
- **Stage:** <!-- FILL IN: idea / prototype / MVP / production -->
- For the owner's background and working style, see `docs/about-me.md`

## What I Need From Agents

- Research before advising - verify current facts (pricing, APIs, legal) before recommending
- When writing code, explain what you're doing and why in plain language
- If uncertain, say so explicitly - never fabricate facts or statistics
- Skip long preambles - get to the point
- Flag when professional review is needed (lawyer, accountant, security auditor)
- Default to actionable advice that can be executed this week

## Current State - Source of Truth Pointers

**This file does NOT own current priorities, active deadlines, or in-progress work.** Those change
too fast for a static config file. Read the live sources below before acting on anything that
depends on what's currently active or due:

- **Active issues + priorities** - <!-- FILL IN: issue tracker URL (Linear, GitHub Issues, ...) -->
- **Decision history (what was decided, when, why)** - `docs/decision-log.md`
- **Known bug patterns** - `docs/common-gotchas.md`

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
├── .cursor/                 # Cursor adapter (rules + hooks + skill routers)
├── .grok/                   # Grok Build adapter (config + hooks)
├── .githooks/               # real git pre-push hook (opt-in push gate)
├── bin/                     # verify-green, git-hook installer, harness hook adapter
└── brain/                   # optional local knowledge base (see brain/README.md)
```

If this project outgrows a single repo (second repo, non-code assets piling up), see
`docs/growing-into-a-workspace.md` for the graduation path.

## Harness Wiring (summary)

The knowledge in this file and `docs/` is harness-agnostic; each tool gets only a thin adapter:

| Harness | Wiring |
|---|---|
| Claude Code | `CLAUDE.md` (imports this file) + hooks via `.claude/settings.json` |
| Cursor | `.cursor/rules/project.mdc` (always-on rule) + `.cursor/hooks.json` (guardrail parity) + `.cursor/skills/*` (routers) |
| Grok Build | `.grok/config.toml` (reuses `.claude/` skills and commands) + `.grok/hooks/hooks.json` |
| Codex | reads this file natively - no adapter needed |
| Gemini CLI | `GEMINI.md` pointer |
| GitHub Copilot | `.github/copilot-instructions.md` pointer |

Claude, Cursor, and Grok all run the SAME hook scripts (via `bin/run-claude-hook.sh` for the
latter two) - guardrail logic exists once. Where a harness runs no hooks at all, agents must
still honor the rules the hooks enforce (don't edit secrets, verify before push).

Skills and command protocols work the same way: one canonical body under `.claude/`, and a thin
router for any harness that cannot load it directly. **While an adapter is present, a new skill
or command needs its router in the same commit** - a procedure the harness cannot reach looks
exactly like one that was never written. Each adapter's own directory documents its router
format; delete the adapter and the rule goes with it.

## Rules

### Working Methodology

- **Plan first for non-trivial tasks** (3+ steps or architectural decisions) - write the plan,
  confirm before implementing. If something goes wrong mid-implementation, STOP and re-plan.
- **Verify before marking done** - never claim a task is complete without proving it works. Run
  tests, check logs, demonstrate correctness. Ask: "Would a staff engineer approve this?"
  If the push gate is configured (`bin/verify-green.sh`), record the proof with
  `bash bin/verify-green.sh` before pushing - unverified pushes are blocked.
- **Grade every claim on the certainty ladder, and say where it stopped.** Five levels:
  (1) *you said so* - worthless on its own; (2) *you pointed at the line* - a real `file:line`,
  or the dependency's own source; (3) *you showed the bad case can't reach* - you walked the
  failure path step by step and it doesn't get there; (4) *you ran it* - a script or test that
  calls the real code and fails loud if you're wrong; (5) *you reproduced it in the running
  app*. Get each claim as far down as is cheap and **name the level out loud**. A claim you
  can't get to 4 is reported as unproven, never written up as settled, and never rounded up.
  Two habits come with it:
  - **Find the one fact the work is safe because of.** Most alarming-looking changes are safe
    because of a single fact ("this only drops already-dead cache entries"). Proving that one
    fact kills the whole list of maybes, so spend the effort there rather than enumerating
    risks.
  - **A writeup that sounds right is worthless.** It reads as convincing whether or not it is
    true, which is exactly the trap. Prose is not evidence; a run is.

  This is the vocabulary the rest of these rules use. "Mutate the suite"
  (`docs/methodology/tdd.md`) is what makes a level-4 claim trustworthy, and the push gate
  records level 4 for a whole tree.
- **Autonomous bug fixing** - when given a bug report, follow `docs/methodology/bug-protocol.md`
  automatically. If details are missing, ask for them.
- **TDD by default** - for code work, follow `docs/methodology/tdd.md`. Write failing tests first,
  then implement.
- **Simplicity first** - make every change as simple as possible. Minimize code impact. No
  temporary fixes - find root causes.

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
  scans - route through a subagent so only the conclusion hits the main context. Mental test:
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
  stop - not grind tokens on it.
- **Don't delegate the trivial.** Single-fact lookups, one-file edits, anything faster to do than
  to brief - do it yourself.

| Tier | Best for | Delegate to it when |
|---|---|---|
| Fast <!-- FILL IN: current model --> | Bulk mechanical work: exhaustive greps, file inventories, formatting | Output is large, judgment is minimal, correctness is cheap to verify |
| Mid <!-- FILL IN --> | Routine implementation following an established pattern | The pattern exists in the repo and a review pass will catch mistakes |
| Strong <!-- FILL IN --> | Complex implementation, debugging, refactors, code review | The task needs real reasoning within known constraints |
| Frontier <!-- FILL IN --> | Architecture decisions, auth/security design, ambiguous tradeoffs | One-shot hard calls; the escalation target |

Refresh the model names when the model family turns over; the tier structure is the stable part.

### Content Rules

- Never fabricate statistics or market data - search first
- All externally-facing content must be original - no copying from competitors
- <!-- OPTIONAL, keep or delete: --> No em dashes (—) in externally-facing content (marketing
  copy, user-facing UI text, emails to outside parties, public posts). Use hyphens, commas,
  parentheses, or separate sentences. Em dashes are fine in internal docs, code comments, and
  commit messages.
- <!-- OPTIONAL, keep or delete: --> **Writing rules for prose (Orwell, 1946).** Scope: the
  externally-facing content above, plus PR descriptions and commit messages. Prose only, never
  code, identifiers, or established technical terms; swap in everyday words only where
  precision survives.
  1. Never use a metaphor or figure of speech you are used to seeing in print.
  2. Never use a long word where a short one will do.
  3. If it is possible to cut a word out, cut it out.
  4. Never use the passive where you can use the active.
  5. Never use jargon or a scientific word where everyday English will do.
  6. Break any of these rules sooner than write something clumsy.
- <!-- OPTIONAL, keep or delete: --> **Banned in that same scope**, as a mechanical check like
  the em-dash rule: *comprehensive, robust, seamless, leverage* (as a verb), *delve, utilize,
  game-changer*; the "it's not just X, it's Y" construction; rule-of-three padding ("faster,
  smarter, better"); achievement language in commits and PRs ("significantly improved",
  "greatly enhanced"), which should state what changed and why in plain words. This is a
  starter list. Extend it as new tells show up, and consider wiring it into a lint script so
  it fails rather than relying on memory.

### Autonomous Housekeeping (do these WITHOUT being asked)

**After every bug fix:**
- Append the symptom / root cause / fix to `docs/common-gotchas.md`.

**After every completed task (feature, bug fix, refactor):**
- Commit the changes with a descriptive message. Stage only the relevant files (never .env,
  secrets, or lock files unless intentional).
- Push to the remote branch. If on a feature branch, offer to create a PR.

**After making or discovering a project decision:**
- Append a one-line entry to `docs/decision-log.md`
  (format: `- **YYYY-MM-DD** - Decision description. See <issue-ref>.`)
- **Date entries in machine-local time, not the session-context date.** The "today's date" an
  agent sees in its context is often UTC-derived and rolls over during the local evening, so
  evening sessions get tomorrow's date. Run `date +%Y-%m-%d` before dating any log entry or
  dated doc. (This future-dated real log entries twice in the project this template came from.)

**After fixing a recurring issue or learning a new codebase pattern:**
- Update this file if it's a convention agents need every session
- Update `docs/common-gotchas.md` if it's a symptom-to-fix pattern

**When new knowledge contradicts recorded knowledge (write-time invalidation):**
- Update or supersede the old entry in the SAME session you write the new one - never write a
  new fact and leave the contradicted one live for retrieval or future greps to keep serving.
  Periodic lint passes are backstops, not the mechanism.
- Supersede, don't delete: memory entries with metadata support get `superseded_by: <successor>`
  and stay on disk; gotchas/docs get edited in place (git history preserves the old text).

**When context files get stale:**
- If this file drifts on stable conventions, flag it and suggest updates
- If the issue tracker is out of date based on something that just happened, flag it - do not
  change tracker priorities or close issues autonomously without permission

## Formatting Preferences

- Use bullet points for action items
- Use Markdown: sections, tables, numbered lists where appropriate
- When writing externally-facing content, align with the brand voice
  (<!-- FILL IN: link brand/voice doc when one exists -->)
- When writing internal/working docs, prioritize clarity and speed
