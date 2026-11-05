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
| `bin/trellis-survey.sh` | Read-only check of static wiring and setup: missing scripts, missing skill routers, Git hook installation, and unfinished context files. Runtime activation and trust are checked separately in SETUP.md. |
| `DESIGN.md` | Design defaults your agent reads before it builds UI: name every value as a token, treat repeats as components, decide every state up front. No colours or type choices - those are yours, and the file has slots for them. Delete or override freely. |
| `docs/methodology/` | Battle-tested working rules: test-first development, a disciplined bug-fix protocol, why a second model should review anything you would hate to get wrong, and habits for keeping AI sessions sharp. Plain markdown, works with any tool. |
| `docs/common-gotchas.md` | A running "symptom, cause, fix" table. Your AI appends to it after every bug fix, so the same bug never costs you twice. |
| `docs/decision-log.md` | What you decided, when, and why - at whatever length the reasoning takes. Six months from now, this is the file that answers "why did I do it that way?". |
| `docs/about-me.md` | Tell the AI who you are (technical level, working style) so its advice actually fits you. |
| `.claude/` | Claude Code extras: guardrail hooks (blocks edits to secrets, auto-formats code, injects context on session start), slash commands, and skills - a ranked daily brief, feature planning, safe dependency reviews, a pre-demo audit. |
| `.githooks/` + `bin/verify-green.sh` | An optional push gate for humans and agents. Install it with `bash bin/install-git-hooks.sh`, configure your lint/test commands, then verify the staged content before pushing. Off until checks are configured; supported session hooks also repair missing wiring. |
| Harness adapters | Cursor, Grok Build, and Codex call the same canonical guardrail scripts as Claude Code. Codex uses `.agents/skills/` routers and `.codex/hooks.json` (requires trust). Gemini CLI and Copilot have instruction pointers. `docs/harness-support.md` records coverage and limitations; the Git push gate and CI work independently of the coding tool. |
| `brain/` | Optional: a local search index over your project's docs and history that feeds relevant context into every prompt. Off by default; 10 minutes to enable when the project has real history. |
| `docs/growing-into-a-workspace.md` | The graduation path for when your project becomes a company: where legal docs, brand assets, and a second repo go, and how the AI context scales with you. |
| `docs/writing-your-own-skills.md` | The 10-minute guide to teaching your AI a repeatable procedure, plus a six-question hardening checklist for making skills that survive contact with reality. |
| `CREDITS.md` | Whose ideas these are. This template is an extraction, not an invention - every borrowed rule and every recommended tool is named with its source, and CI fails if a recommendation has no credit line. |
| Hooks CI | A tiny GitHub Actions workflow that lint-gates the guardrail scripts themselves (line endings, syntax, shellcheck, exec bits) - because a hook that breaks silently is worse than no hook. |
| Leak check and secret scan | `bin/check-leaks.py` fails CI when a tracked file names something on your private list. `.gitleaks.toml` adds rules for the key formats this template's docs mention, and CI scans the working tree and the pushed commits with it. Both say so when they have nothing to check. |

## Skills

A skill is a repeatable procedure your agent loads when it needs it. These ship in
`.claude/skills/`; the other tools reach them through the routers described in
`docs/harness-support.md`. This table is generated from each skill's front matter by
`python bin/build-skills-catalog.py`, and CI fails when it is stale, so do not edit it by hand.

<!-- skills-catalog:start -->
| Skill | What it does |
| --- | --- |
| [`build-verification-skill`](.claude/skills/build-verification-skill/SKILL.md) | Build this project's verification skill - a small CLI that drives the running app and captures evidence, plus a feature map of what exists and how to reach it - and the CI check that keeps the map current. |
| [`daily-brief`](.claude/skills/daily-brief/SKILL.md) | Start-of-day ranked brief - open issues, recent commits, work in progress, and anything waiting on a human decision. |
| [`grill-design`](.claude/skills/grill-design/SKILL.md) | Decide a UI design by building several genuinely different working prototypes and comparing them side by side, in rounds, until the choice is locked. |
| [`launch-check`](.claude/skills/launch-check/SKILL.md) | Run a pre-demo/pre-launch audit of the app - test data, broken screens, missing error states, brand consistency. |
| [`learn`](.claude/skills/learn/SKILL.md) | Review the current conversation and update project knowledge artifacts - common-gotchas.md (bug patterns), conventions at the highest rung that holds them (code, check, reviewer standard, skill, then AGENTS.md), navigation pointers, agent memory (cross-session). |
| [`pin-guardrail`](.claude/skills/pin-guardrail/SKILL.md) | Pin a shell guardrail (a hook, a git hook, a checker script) with a behavioral test suite, prove the suite is real by mutating the code, and wire it into CI with its mutation ledger. |
| [`prd-to-issues`](.claude/skills/prd-to-issues/SKILL.md) | Break a PRD into independently-grabbable tracker issues using tracer-bullet vertical slices. |
| [`review-dependency-updates`](.claude/skills/review-dependency-updates/SKILL.md) | Review outdated dependencies, security-scan each candidate bump against OSV.dev, then apply only the safe updates and PR them. |
| [`security-audit`](.claude/skills/security-audit/SKILL.md) | Security guidance and vulnerability review for codebases, APIs, services, CLI tools, libraries, and daemons. Use for security questions, focused reviews, vulnerability research, security audits, or pen tests. Run the complete workflow only for explicit codebase audit or pen-test requests, full/comprehensive/end-to-end reviews, or requested report artifacts. |
| [`setup`](.claude/skills/setup/SKILL.md) | Walk a new project through setting up this template - interview the owner, fill in the context files, wire the safety rails, and verify it worked. |
| [`trellis-survey`](.claude/skills/trellis-survey/SKILL.md) | Check this template's static wiring and setup - missing hooks, unreachable skills, unfinished context files. Runtime activation and trust require separate checks. Read-only. |
| [`trellis-sync`](.claude/skills/trellis-sync/SKILL.md) | Check this project against the template it was made from, show what changed upstream, and apply only what the user picks. |
| [`write-a-prd`](.claude/skills/write-a-prd/SKILL.md) | Create a PRD through user interview, codebase exploration, and module design, then submit to the issue tracker. |
<!-- skills-catalog:end -->

## Keeping private names and secrets out

A public repo built from a private project tends to keep the project's names in an example or a
comment. To catch that:

1. Copy `tools/leaks.local.txt.example` to `tools/leaks.local.txt` (git ignores it) and list the
   names, one regular expression per line.
2. Run `python bin/check-leaks.py --require`. It prints the file, the line and the list entry
   number for each match, never the matched text (a matching path is printed masked, and an
   entry that is not a valid pattern is named by number only); add `--show` on your own machine
   to see the text. A tracked symlink is checked by the target path git stores for it, and the
   link is never followed.
3. For CI, put the same text in a repository secret named `LEAKS_LIST`. Without one, CI prints
   `skipped: no list` and a notice, so a skipped check never looks like a pass. GitHub gives no
   secrets to a pull request from a fork, so there the step fails instead: before merging, run
   the check locally with the list, or push the branch to your repository so CI runs it.

Never commit the list: a public repo that carried it would publish the names. For credentials,
`.gitleaks.toml` extends gitleaks' default rules; run `gitleaks detect --no-git --source . --redact`
to scan your working tree. CI scans the working tree and every commit in the push or pull
request, so a key added and then deleted still fails.

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
**Nothing is applied unless you name it.** Even the safe bucket needs an explicit
`--apply <path>`; the report on its own writes nothing. Two buckets need more than a yes: files
changed on both sides, which you review before selecting because taking an update is a
whole-file write, and files upstream deleted that you still have, which the tool will not touch
at all - removing them is your call. Each file it does write is checked against the release it
came from before it lands, and if it can't tell (no manifest, no network) it says so rather than
reporting you as up to date.

This works because `.trellis/manifest` records what the template shipped at the version you
copied. Keep that file, and never regenerate it from your own tree - that records your work as
though the template had shipped it, and every later sync inherits it. `bin/trellis-sync.sh
--apply` updates it for you, for the files you actually took and nothing else.

If you maintain your own fork of the template for your team: improvements land in whichever
project discovered them, then get PR'd back to the template.
