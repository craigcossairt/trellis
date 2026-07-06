# Recommended third-party tooling

Optional, battle-tested third-party skill packs worth installing alongside this template. These
are **user-level installs** (they live in `~/.claude`, shared across all your projects) - install
them once per machine, not per project. They are referenced here rather than vendored so they
update from source and their licensing stays clean.

## Matt Pocock's skills - engineering discipline

Eleven skills that force the agent to slow down: grill you on the plan, run a real debug loop,
zoom out before architecting. (`/grill-me`, `/grill-with-docs`, `/diagnose`, `/zoom-out`,
`/improve-codebase-architecture`, `/to-prd`, `/to-issues`, `/caveman`, `/write-a-skill`, ...)

```bash
npx skills@latest add mattpocock/skills
```

The installer is interactive - pick the skills you want and which coding agents to install them
for, then run `/setup-matt-pocock-skills` inside your agent.

**Collision warning:** his `tdd` and `implement` skills overlap with this template's `/tdd`
command and methodology docs. Pick one TDD authority - either skip installing his `tdd`, or
delete this template's version. Running both gives the agent two conflicting workflows.

Source: https://github.com/mattpocock/skills

## Impeccable - frontend design quality

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

Note: unlike the others, this installs per-project state - which fits, since design context
(audience, brand personality) is per-project.

Source: https://impeccable.style/ (pbakaus/impeccable)

## gstack - virtual engineering team

Opinionated persona commands (CEO product rethink, eng-manager architecture lock, design
critique, security audit, QA in a real browser, release engineer). Heavy install (~GBs: bundled
browser + node_modules) - machine-level, clone once:

```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
cd ~/.claude/skills/gstack && ./setup
```

Source: https://github.com/garrytan/gstack

---

# Services & integrations

The service stack that earned its keep in the production setup this template was extracted
from. Rules of this list: one pick per category (not a directory), each entry says when it
*earns its place*, and the default is always free/built-in until you feel the pain it solves.
You need none of these on day 1.

| Category | Pick | When it earns its place |
|---|---|---|
| Issue tracking | GitHub Issues to start; **Linear** when the backlog outgrows it | Day 1 for Issues (free, zero setup, agents read/write via `gh`). Move to Linear when you're juggling priorities across many issues and need cycles/projects - it has an MCP server, so agents work the backlog directly. |
| Automated PR review | **CodeRabbit** | As soon as you're merging AI-written code you can't fully review yourself - an automated second reader catches real bugs. Free for public repos. Caveat: treat it as a reviewer, not a gate; question its premise before applying a remedy, and never merge on its check status alone - read the actual comments. |
| Error tracking | **Sentry** | The day real users touch the product. Before that, local logs are enough. Free tier is generous for a small app; agents can triage straight from its MCP server. |
| Uptime monitoring | **UptimeRobot** | The day something is deployed that users depend on. Free tier covers a small site. |
| Product analytics | **PostHog** | When you start making product decisions and need evidence instead of vibes. Free tier is generous. |
| CI | **GitHub Actions** | First time a broken push costs you an evening. Start with lint + test on PR; it's free for public repos and cheap for private ones. |
| Secrets | A password manager (**Bitwarden**, 1Password) | Day 1, non-negotiable. Real values live there; repos get `.example` files only. The template's hooks enforce the repo side. |

Pricing and free-tier limits change - verify current terms before committing to a paid plan.

## Adding to this list

Criteria for a skill-pack entry: actively maintained, installable from source with one command,
and worth recommending to a teammate on day 1. Note any collisions with this template's
commands/skills.

Criteria for a service entry: it earned its keep in a real project, has a usable free tier or
clear pricing, and ideally has an MCP server or CLI so agents can operate it, not just humans.
