# Recommended third-party tooling

Optional, battle-tested third-party skill packs worth installing alongside this template. These
are **user-level installs** (they live in `~/.claude`, shared across all your projects) — install
them once per machine, not per project. They are referenced here rather than vendored so they
update from source and their licensing stays clean.

## Matt Pocock's skills — engineering discipline

Eleven skills that force the agent to slow down: grill you on the plan, run a real debug loop,
zoom out before architecting. (`/grill-me`, `/grill-with-docs`, `/diagnose`, `/zoom-out`,
`/improve-codebase-architecture`, `/to-prd`, `/to-issues`, `/caveman`, `/write-a-skill`, ...)

```bash
npx skills@latest add mattpocock/skills
```

The installer is interactive — pick the skills you want and which coding agents to install them
for, then run `/setup-matt-pocock-skills` inside your agent.

**Collision warning:** his `tdd` and `implement` skills overlap with this template's `/tdd`
command and methodology docs. Pick one TDD authority — either skip installing his `tdd`, or
delete this template's version. Running both gives the agent two conflicting workflows.

Source: https://github.com/mattpocock/skills

## Impeccable — frontend design quality

Builds on Anthropic's frontend-design skill: 23 commands (`polish`, `audit`, `critique`,
`animate`, ...), 45 deterministic anti-"AI slop" detector rules, curated styles/palettes/font
pairings, 8 stacks (React, Next.js, Vue, Svelte, SwiftUI, React Native, Flutter, Tailwind).
Harness-agnostic: works with Claude Code, Cursor, Copilot, Gemini CLI, Codex.

```bash
# from the project root
npx impeccable install
# then inside your coding agent:
/impeccable init
```

Note: unlike the others, this installs per-project state — which fits, since design context
(audience, brand personality) is per-project.

Source: https://impeccable.style/ (pbakaus/impeccable)

## gstack — virtual engineering team

Opinionated persona commands (CEO product rethink, eng-manager architecture lock, design
critique, security audit, QA in a real browser, release engineer). Heavy install (~GBs: bundled
browser + node_modules) — machine-level, clone once:

```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
cd ~/.claude/skills/gstack && ./setup
```

Source: https://github.com/garrytan/gstack

## Adding to this list

Criteria for an entry: actively maintained, installable from source with one command, and worth
recommending to a teammate on day 1. Note any collisions with this template's commands/skills.
