# trellis

![License: MIT](https://img.shields.io/badge/license-MIT-4ECDC4) ![Works with](https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20Cursor%20%C2%B7%20Grok%20Build%20%C2%B7%20Codex%20%C2%B7%20Gemini%20%C2%B7%20Copilot-FF7A6B)

A trellis is the structure a plant grows on. This one is for projects: a ready-to-use template
for building with AI coding agents - extracted from the real, daily-driven setup of a production
startup, then stripped of everything company-specific.

**Who this is for:** founders and builders who are new to AI-assisted development ("vibe-coding")
and want to start with good habits instead of discovering them the hard way. You don't need to be
an experienced engineer. Setup involves a handful of terminal commands, and your AI can walk you
through every one of them - open the repo and say *"walk me through SETUP.md"*.

It also works as a no-ceremony starting point if you already build this way, and as a reference
if you have an existing project and want to see what's worth borrowing.

**The problem it solves:** AI coding tools are powerful on day 1 and chaotic by day 30. Without
structure, you get inconsistent code, forgotten decisions, repeated bugs, secrets in git, and an
AI that re-learns your project from scratch every session. This template bakes in the structure
that prevents that - before the chaos starts.

## What you get

| Piece | What it does for you |
|---|---|
| `AGENTS.md` | One instruction file that every major AI tool reads (Claude Code, Cursor, Codex, Gemini CLI, Copilot). Your conventions, methodology, and project facts live here once - not re-explained every session. |
| `SETUP.md` | Day-1 setup, two ways: let your AI interview you and make the edits, or follow the checklist yourself. About 15 minutes for the core steps, plus a couple of optional extras. Explains what each piece is before asking you to touch it. |
| `docs/methodology/` | Battle-tested working rules: test-first development, a disciplined bug-fix protocol, why a second model should review anything you would hate to get wrong, and habits for keeping AI sessions sharp. Plain markdown, works with any tool. |
| `docs/common-gotchas.md` | A running "symptom, cause, fix" table. Your AI appends to it after every bug fix, so the same bug never costs you twice. |
| `docs/decision-log.md` | What you decided, when, and why - at whatever length the reasoning takes. Six months from now, this is the file that answers "why did I do it that way?". |
| `docs/about-me.md` | Tell the AI who you are (technical level, working style) so its advice actually fits you. |
| `.claude/` | Claude Code extras: guardrail hooks (blocks edits to secrets, auto-formats code, injects context on session start), slash commands, and skills - a ranked daily brief, feature planning, safe dependency reviews, a pre-demo audit. |
| `.githooks/` + `bin/verify-green.sh` | An optional push gate that works for humans AND agents: once you fill in your lint/test commands, `git push` refuses any commit whose checks were never seen passing. Off by default; self-installs its wiring at session start. |
| Harness adapters | Cursor and Grok Build run the same guardrail hooks as Claude Code through one shared adapter (`bin/run-claude-hook.sh`) - plus pointer files for Gemini CLI and GitHub Copilot. Codex reads AGENTS.md natively. Every tool gets the rules; three of the six also run the hooks. `docs/harness-support.md` says exactly which features work where, and the push gate and CI cover the rest because they sit outside the session. |
| `brain/` | Optional: a local search index over your project's docs and history that feeds relevant context into every prompt. Off by default; 10 minutes to enable when the project has real history. |
| `docs/growing-into-a-workspace.md` | The graduation path for when your project becomes a company: where legal docs, brand assets, and a second repo go, and how the AI context scales with you. |
| `docs/writing-your-own-skills.md` | The 10-minute guide to teaching your AI a repeatable procedure, plus a six-question hardening checklist for making skills that survive contact with reality. |
| `CREDITS.md` | Whose ideas these are. This template is an extraction, not an invention - every borrowed rule and every recommended tool is named with its source, and CI fails if a recommendation has no credit line. |
| Hooks CI | A tiny GitHub Actions workflow that lint-gates the guardrail scripts themselves (line endings, syntax, shellcheck, exec bits) - because a hook that breaks silently is worse than no hook. |

## Quick start

1. Click **Use this template** on GitHub (or run
   `gh repo create my-project --template craigcossairt/trellis`).
2. Open your new repo in your AI coding tool and say **"walk me through SETUP.md"**. It asks the
   setup questions conversationally, makes the edits for you, and shows you each change before
   it saves. Prefer to do it by hand? **SETUP.md** is the same steps as a checklist, about
   15 minutes.
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

Template copies still don't auto-update, but you no longer have to read commits to find out
what changed. Ask your agent to **check for template updates**, or run:

```bash
bash bin/trellis-sync.sh
```

It compares your copy against the current release by content and sorts every file into one of
six buckets - changed upstream but not by you, new upstream, changed on both sides, and so on.
Two buckets need a decision from you: files changed on both sides, and files upstream deleted
that you still have. Nothing is written until you pick it, each file it writes is checked against
the release it came from before it lands, and if it can't tell (no manifest, no network) it says
so rather than reporting you as up to date.

This works because `.trellis/manifest` records what the template shipped at the version you
copied. Keep that file, and never regenerate it from your own tree - that records your work as
though the template had shipped it, and every later sync inherits it. `bin/trellis-sync.sh
--apply` updates it for you, for the files you actually took and nothing else.

If you maintain your own fork of the template for your team: improvements land in whichever
project discovered them, then get PR'd back to the template.
