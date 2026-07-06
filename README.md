# project-starter

A batteries-included template for starting a new project with an AI-agent-optimized workflow
already in place. Extracted and generalized from a production solo-founder setup.

## What you get

| Piece | What it does |
|---|---|
| `AGENTS.md` | Canonical agent instructions (harness-agnostic: Claude Code, Cursor, Codex, Gemini CLI all read it). Methodology, housekeeping rules, delegation guidance, with FILL-IN slots for your stack. |
| `CLAUDE.md` | Thin pointer that imports AGENTS.md for Claude Code. |
| `docs/methodology/` | TDD workflow, bug-fix protocol, session-management habits — plain markdown, works with any tool. |
| `docs/common-gotchas.md` | Empty scaffold for the symptom → root cause → fix table. Agents append to it after every bug fix. |
| `docs/decision-log.md` | Empty scaffold for one-line decision history. |
| `.claude/` | Claude Code adapter: hooks (session context, sensitive-file block, format-on-edit), slash commands (`/tdd`, `/bug-report`, `/worktree`), skills (`/learn`, `/write-a-prd`, `/prd-to-issues`, `/launch-check`, `/review-dependency-updates`), and a security-reviewer agent. |
| `.cursor/`, `GEMINI.md`, `.github/copilot-instructions.md` | Thin adapters pointing at AGENTS.md for Cursor, Gemini CLI, and GitHub Copilot. Codex reads AGENTS.md natively — no adapter needed. |
| `docs/growing-into-a-workspace.md` | The graduation path for when the project becomes a venture: workspace root with `Files/` + `Code/<repos>`, two-level AGENTS.md, migration steps. |
| `brain/` | Optional local knowledge base: BM25 search over your project corpus, auto-injected into every prompt via hook. Off by default until you initialize it. |

## Quick start

1. Click **Use this template** on GitHub (or `gh repo create my-project --template <owner>/project-starter`).
2. Open the new repo and work through **SETUP.md** — it's a 15-minute checklist.
3. Delete what you don't need. Every piece is independent; nothing breaks if you remove a skill,
   the brain, or an adapter.

## Design principles

- **Harness-agnostic core, thin adapters.** The knowledge (AGENTS.md + docs/) is plain markdown
  any tool can read. Tool-specific machinery stays in that tool's directory and is progressive
  enhancement, never a requirement.
- **Source-of-truth discipline.** AGENTS.md owns stable conventions only. Priorities live in the
  issue tracker. Decisions live in the decision log. Bug patterns live in common-gotchas. Nothing
  is written twice.
- **No secrets, ever.** `.env.example` and `.mcp.json.example` ship placeholders. Real values come
  from your password manager at setup time.

## Maintaining the template

Improvements land in whichever project discovered them first. Once a month, ask: *"Did anything
this month belong upstream in project-starter?"* and PR it back here. Template consumers pull
improvements manually — copies do not auto-update.
