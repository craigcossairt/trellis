# trellis

![License: MIT](https://img.shields.io/badge/license-MIT-4ECDC4) ![Works with](https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20Cursor%20%C2%B7%20Codex%20%C2%B7%20Gemini%20%C2%B7%20Copilot-FF7A6B)

A trellis is the structure a plant grows on. This one is for projects: a ready-to-use template
for building with AI coding agents - extracted from the real, daily-driven setup of a production
startup, then stripped of everything company-specific.

**Who this is for:** founders and builders who are new to AI-assisted development ("vibe-coding")
and want to start with good habits instead of discovering them the hard way. You don't need to
be an engineer. If you can follow a checklist, you can use this.

**The problem it solves:** AI coding tools are powerful on day 1 and chaotic by day 30. Without
structure, you get inconsistent code, forgotten decisions, repeated bugs, secrets in git, and an
AI that re-learns your project from scratch every session. This template bakes in the structure
that prevents that - before the chaos starts.

## What you get

| Piece | What it does for you |
|---|---|
| `AGENTS.md` | One instruction file that every major AI tool reads (Claude Code, Cursor, Codex, Gemini CLI, Copilot). Your conventions, methodology, and project facts live here once - not re-explained every session. |
| `SETUP.md` | A day-1 checklist: about 15 minutes for the core steps, plus a couple of optional extras. Fill in the blanks, delete what you don't need. |
| `docs/methodology/` | Battle-tested working rules: test-first development, a disciplined bug-fix protocol, and habits for keeping AI sessions sharp. Plain markdown, works with any tool. |
| `docs/common-gotchas.md` | A running "symptom, cause, fix" table. Your AI appends to it after every bug fix, so the same bug never costs you twice. |
| `docs/decision-log.md` | One line per decision. Six months from now you'll know what you decided and why. |
| `docs/about-me.md` | Tell the AI who you are (technical level, working style) so its advice actually fits you. |
| `.claude/` | Claude Code extras: guardrail hooks (blocks edits to secrets, auto-formats code, injects context on session start), slash commands, and skills - a ranked daily brief, feature planning, safe dependency reviews, a pre-demo audit. |
| Harness adapters | Thin pointer files for Cursor, Gemini CLI, and GitHub Copilot. Codex reads AGENTS.md natively. Use any tool, or several. |
| `brain/` | Optional: a local search index over your project's docs and history that feeds relevant context into every prompt. Off by default; 10 minutes to enable when the project has real history. |
| `docs/growing-into-a-workspace.md` | The graduation path for when your project becomes a company: where legal docs, brand assets, and a second repo go, and how the AI context scales with you. |

## Quick start

1. Click **Use this template** on GitHub (or run
   `gh repo create my-project --template craigcossairt/trellis`).
2. Open your new repo and work through **SETUP.md** - a 15-minute checklist.
3. Delete what you don't need. Every piece is independent; nothing breaks if you remove a
   skill, the brain, or an adapter you don't use.
4. Optional but recommended: skim `docs/recommended-tooling.md` for curated third-party
   skill packs and the service stack (issue tracking, PR review, error tracking) that
   earned its keep in the setup this template came from.

## Design principles

- **Tool-agnostic core, thin adapters.** The knowledge (AGENTS.md + docs/) is plain markdown
  any tool can read. Tool-specific machinery stays in that tool's directory and is optional
  enhancement, never a requirement. Switch tools without losing your setup.
- **Source-of-truth discipline.** Stable conventions live in AGENTS.md. Priorities live in your
  issue tracker. Decisions live in the decision log. Bug patterns live in the gotchas table.
  Nothing is written twice, so nothing drifts.
- **No secrets, ever.** `.env.example` and `.mcp.json.example` ship placeholders only. Real
  values come from your password manager at setup time, and a guardrail hook blocks the AI from
  editing secret files.

## Support expectations

This is maintained as I use it for my own projects. Issues and PRs are welcome and read, but
responses aren't guaranteed and there is no support commitment. Fork freely - it's MIT licensed.

## Keeping your copy fresh

Template copies don't auto-update. Once a month, skim this repo's recent commits and pull in
what's useful. If you maintain your own fork of the template for your team: improvements land
in whichever project discovered them, then get PR'd back to the template.
