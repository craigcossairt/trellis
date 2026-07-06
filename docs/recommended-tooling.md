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
| Backend | **Supabase** (if you need a database + auth) | Day 1 if your product stores user data and you don't have strong stack opinions: Postgres, auth, storage, and functions in one, generous free tier, and an MCP server so agents can manage the schema. If you do have stack opinions, use them - this row is a default, not a mandate. |
| Web hosting | **Vercel** | The day you have a web app or site to put in front of anyone. Free hobby tier, git-push deploys, and MCP/CLI so agents can ship and inspect deployments. |
| Dependency security | **OSV.dev** to start; **Socket** for supply-chain depth | OSV is day 1 - free, no signup, already wired into this template's `/review-dependency-updates` skill. Add Socket when you want supply-chain risk scoring (maintainer changes, install scripts) beyond known CVEs. |
| Docs & knowledge | Markdown in the repo to start; **Notion** at company stage | This template's whole philosophy: docs live in git where agents read them for free. Notion earns its place when non-code collaborators and business ops appear (see `growing-into-a-workspace.md`). |
| Codebase audits | **AuditBuffet** | Pre-launch, or whenever you suspect the AI has quietly accumulated slop. Audit prompts run locally inside your coding agent (your code never leaves your machine); free basic scan, ~$9/mo for the full catalog at time of writing. |
| Design & visuals | Your coding agent + a design skill to start; **Claude Design** for visuals beyond the app; **Figma** when a designer joins | Most solo founders need less design tooling than they think - the Impeccable skill above covers in-app UI. Claude Design (Anthropic, research preview) earns its place for decks, one-pagers, and landing mockups. Figma when you collaborate with an actual designer. |

Pricing and free-tier limits change - verify current terms before committing to a paid plan.

## Adding to this list

Criteria for a skill-pack entry: actively maintained, installable from source with one command,
and worth recommending to a teammate on day 1. Note any collisions with this template's
commands/skills.

Criteria for a service entry: it earned its keep in a real project, has a usable free tier or
clear pricing, and ideally has an MCP server or CLI so agents can operate it, not just humans.
