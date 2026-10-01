# Harness support

Which parts of this template are wired for each AI coding tool, and what activates them.

The knowledge in `AGENTS.md` and `docs/` is plain markdown and works everywhere. The automation
is not: hooks, skills and subagents each depend on the tool, its version, project trust, and
local dependencies. Two of the six adapters below supply no session hooks. A configured hook
is not proof that it ran; use the live checks in `SETUP.md` after activating your tool.

Updated 2026-09-30. This table describes the files shipped here, not every feature a tool offers.

## What runs where

| | Claude Code | Cursor | Grok Build | Codex | Gemini CLI | Copilot |
|---|---|---|---|---|---|---|
| Reads `AGENTS.md` | yes | yes | yes | yes | yes | yes |
| Session-start context | wired | wired | wired | wired | **no** | **no** |
| Sensitive-file check on supported edit tools | wired | wired | wired | `apply_patch` | **no** | **no** |
| Formats on edit | wired | wired | wired | `apply_patch` | **no** | **no** |
| Injects `brain/` context | wired | **no** | wired | wired | **no** | **no** |
| Skills | yes | via routers | yes | via `.agents/skills` | **no** | **no** |
| Command protocols | slash commands | via routers | slash commands | via skill routers | **no** | **no** |
| Shipped `.claude/agents` personas | yes | **no** | yes | **no** | **no** | **no** |
| Git push gate, after install and configuration | yes | yes | yes | yes | yes | yes |
| Hooks CI, on GitHub | yes | yes | yes | yes | yes | yes |

## The two rows that are green everywhere

This is the part worth understanding, because it is what keeps the template useful on a tool
that runs none of its hooks.

**The push gate is a git hook, not a harness hook.** `.githooks/pre-push` runs inside `git push`
itself, so it applies to every tool and to you typing in a terminal. Install it explicitly with
`bash bin/install-git-hooks.sh` and configure `GREEN_COMMANDS` in `bin/verify-green.sh`. The gate
requires a receipt for the pushed tree. Verification refuses unstaged tracked changes and
non-ignored untracked inputs, so checks run against the content being certified. Ignored build
outputs and dependencies remain allowed. Local Git hooks can be bypassed; they are not a server
policy.

Verification refuses `assume-unchanged` and `skip-worktree` flags, which can hide working-tree
changes from Git. It leaves those flags untouched. Use a full checkout for this gate; sparse
checkouts are not supported.

**Hooks CI runs on GitHub.** It checks the guardrail scripts and adapters on every pull request,
whichever tool opened it. Make its checks required in branch protection if you want failures to
block merges. This template cannot configure an adopter's branch protection.

On an adapter with no session hooks, the agent follows the instructions without those runtime
checks. The Git gate and CI still work when installed and configured, but neither replaces a
project's own tests or proves that every edit tool is guarded.

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
`.grok/config.toml` reuses `.claude/` skills, commands and
subagents directly, so there are no routers to keep in sync, and `.grok/hooks/hooks.json` runs all
four guardrails through the same shared adapter. Unlike Cursor, its prompt hook can inject
`brain/` context. Run `/hooks-trust` the first time you open the project or no project hook fires.

### Codex
Reads `AGENTS.md` natively. Thin routers under `.agents/skills/` expose every retained canonical
skill and command as a Codex skill, such as `$setup` and `$worktree`. Keep the routers in the
same commit as changes to the canonical procedures. Codex supports subagents, but the shipped
Claude agent personas are not automatically converted into Codex agent definitions.

`.codex/hooks.json` configures four command hooks through `.codex/hooks.py`, which calls the
same canonical shell scripts. It needs Python 3.10+, Git, and Bash. Trust the project, then use
`/hooks` in Codex CLI to review and trust the hook definitions. Changes require renewed trust.
See `.codex/README.md` for setup and the [OpenAI hook documentation](https://learn.chatgpt.com/docs/hooks)
for version-specific behavior.

The edit adapter checks all `apply_patch` targets, including deletes and both sides of renames.
It refuses malformed input, paths outside the repository, missing policy scripts, and failed
policy execution. Shell commands and other file-writing tools are outside this path check.
Keep sandbox and permission controls enabled. The static validator and survey check files and
wiring; they cannot prove that an interactive session trusted or ran a hook.

### Gemini CLI
`GEMINI.md` points at `AGENTS.md`. No hooks or skill adapter are shipped here. Advisory, plus
the configured Git push gate and CI.

### GitHub Copilot
`.github/copilot-instructions.md` points at `AGENTS.md`. No hooks or skill adapter are shipped
here. Advisory, plus the configured Git push gate and CI.

## Windows

The Cursor and Grok hook configs invoke `bash`. On Windows a bare `bash` can resolve to the WSL
stub, where `HOME` and every path are wrong and the hooks fail in confusing ways. Replace it with
Git Bash's full path in both files:

```text
"C:/Program Files/Git/bin/bash.exe" bin/run-claude-hook.sh cursor session-start
```

Claude's `$CLAUDE_PROJECT_DIR` resolves script paths, but does not choose the Bash executable.
Check its selected shell too. Codex's Windows launcher uses Python through the selected shell; the adapter
locates Git Bash from Git for Windows. Use a device-local `TRELLIS_BASH` override if needed.
Do not commit a machine-specific user path into shared configuration.

CI runs the behavioral suites on Linux and Windows. Permission and executable-bit cases that
NTFS cannot represent are reported as skips on Windows and run on Linux.

## If your tool is not listed

Two things make a tool usable with this template, in order:

1. **A pointer file it reads at session start**, saying `AGENTS.md` is canonical. That alone gets
   you the rules, which is most of the value. Copy `GEMINI.md` and rename it.
2. **A hook config**, if the tool has one. Adapt its input and output while reusing the policy
   in `.claude/hooks/`. `bin/run-claude-hook.sh` handles Cursor/Grok payloads; `.codex/hooks.py`
   handles multi-file patches and Codex context output. Cover the new adapter with behavioral
   tests before claiming support.

Add a column here in the same commit. A tool supported in the repo but missing from this table is
indistinguishable from one that was never supported.
