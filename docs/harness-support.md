# Harness support

Which parts of this template actually run, in which AI coding tool.

The knowledge in `AGENTS.md` and `docs/` is plain markdown and works everywhere. The automation
is not: hooks, skills and subagents each depend on what a given tool supports, and three of the
six tools below run no hooks at all. This page says which cells are empty, because a table that
only lists what works reads as full coverage.

Accurate as of 2026-09-21, against this repo's `main`.

## What runs where

| | Claude Code | Cursor | Grok Build | Codex | Gemini CLI | Copilot |
|---|---|---|---|---|---|---|
| Reads `AGENTS.md` | yes | yes | yes | yes | yes | yes |
| Session-start context | yes | yes | yes | **no** | **no** | **no** |
| Blocks edits to secrets | yes | yes | yes | **no** | **no** | **no** |
| Formats on edit | yes | yes | yes | **no** | **no** | **no** |
| Injects `brain/` context | yes | **no** | yes | **no** | **no** | **no** |
| Skills | yes | via routers | yes | **no** | **no** | **no** |
| Slash commands | yes | via routers | yes | **no** | **no** | **no** |
| Subagents | yes | **no** | yes | **no** | **no** | **no** |
| Push gate | yes | yes | yes | yes | yes | yes |
| Hooks CI | yes | yes | yes | yes | yes | yes |

## The two rows that are green everywhere

This is the part worth understanding, because it is what keeps the template useful on a tool
that runs none of its hooks.

**The push gate is a git hook, not a harness hook.** `.githooks/pre-push` runs inside `git push`
itself, so it applies to every tool and to you typing in a terminal. If it is configured, nothing
reaches the remote without its checks having been recorded, regardless of what wrote the code.

**Hooks CI runs on GitHub.** It gates the guardrail scripts themselves on every pull request,
whichever tool opened it.

So on a tool with no hook support, you lose the in-session guardrails and keep the ones at the
boundary. That is a real downgrade, not a disaster: nothing bad reaches `main` unnoticed, but
you find out later rather than at the moment of the mistake.

## Per-tool notes

### Claude Code
Everything is wired. `CLAUDE.md` imports `AGENTS.md`; four hooks in `.claude/settings.json`;
skills, commands and subagents load natively from `.claude/`.

### Cursor
Guardrail parity through `.cursor/hooks.json`, which calls the same canonical scripts via
`bin/run-claude-hook.sh`. Two things to know:

- **No `brain/` injection.** Cursor cannot add prompt context from `beforeSubmitPrompt`. The hook
  is wired and best-effort, but do not count on it - on substantive prompts, ask the agent to
  search the brain, or query it through an MCP server.
- **Skills need a router.** Every canonical skill and command needs a matching file under
  `.cursor/skills/<name>/`, or it is unreachable from Cursor. Hooks CI catches both directions:
  a router pointing at a file that no longer exists, and a skill or command that never got a
  router.

Its hook config declares `failClosed: true` on the block hook, so a hook that errors refuses the
edit rather than waving it through. You must trust the workspace for project hooks to load.

### Grok Build
The fullest support after Claude Code. `.grok/config.toml` reuses `.claude/` skills, commands and
subagents directly, so there are no routers to keep in sync, and `.grok/hooks/hooks.json` runs all
four guardrails through the same shared adapter. Unlike Cursor, its prompt hook can inject
`brain/` context. Run `/hooks-trust` the first time you open the project or no project hook fires.

### Codex
Reads `AGENTS.md` natively, which is why it needs no pointer file. It runs none of the hooks and
has no skill routers on `main`, so every rule is advisory: the agent has to honor them because
nothing is enforcing them. The push gate and CI still apply.

### Gemini CLI
`GEMINI.md` points at `AGENTS.md`. No hooks, no skills. Advisory, plus the push gate and CI.

### GitHub Copilot
`.github/copilot-instructions.md` points at `AGENTS.md`. No hooks, no skills. Advisory, plus the
push gate and CI.

## Windows

The Cursor and Grok hook configs invoke `bash`. On Windows a bare `bash` can resolve to the WSL
stub, where `HOME` and every path are wrong and the hooks fail in confusing ways. Replace it with
Git Bash's full path in both files:

```text
"C:/Program Files/Git/bin/bash.exe" bin/run-claude-hook.sh cursor session-start
```

Claude Code is unaffected - `.claude/settings.json` resolves paths through `$CLAUDE_PROJECT_DIR`.

## If your tool is not listed

Two things make a tool usable with this template, in order:

1. **A pointer file it reads at session start**, saying `AGENTS.md` is canonical. That alone gets
   you the rules, which is most of the value. Copy `GEMINI.md` and rename it.
2. **A hook config**, if the tool has one. Call `bin/run-claude-hook.sh <tool> <hook>` rather than
   writing new hook logic - it adapts the payload and verdict shapes, and the guardrail itself
   stays defined once in `.claude/hooks/`. Adding a tool there means adding its name to that
   script's verdict cases.

Add a column here in the same commit. A tool supported in the repo but missing from this table is
indistinguishable from one that was never supported.
