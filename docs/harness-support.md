# Harness support

Which parts of this template are wired for each AI coding tool, and what activates them.

The knowledge in `AGENTS.md` and `docs/` is plain markdown and works everywhere. The automation
is not: hooks, skills and subagents each depend on the tool, its version, project trust, and
local dependencies. Four of the eight tools below get no session hooks from this template. A
configured hook is not proof that it ran; use the live checks in `SETUP.md` after activating
your tool.

Updated 2026-11-13. This table describes the files shipped here, not every feature a tool offers.

## What runs where

| | Claude Code | Cursor | Grok Build | Codex | Muse Code | Antigravity | Gemini CLI | Copilot |
|---|---|---|---|---|---|---|---|---|
| Reads `AGENTS.md` | yes | yes | yes | yes | yes\* | first 24,000 bytes\* | via `GEMINI.md` | yes |
| Session-start context | wired | wired | shown to you\* (see note) | wired | **no** | **no** | **no** | **no** |
| Sensitive-file check on supported edit tools | wired | wired | wired | `apply_patch` | **no** | **no** | **no** | **no** |
| Formats on edit | wired | wired | wired | `apply_patch` | **no** | **no** | **no** | **no** |
| Injects `brain/` context | wired | **no** | **no** | wired | **no** | **no** | **no** | **no** |
| Skills | yes | via routers | via `.agents/skills` | via `.agents/skills` | via `.agents/skills`\* | via `.agents/skills`\* | via `.agents/skills`\* | **no** |
| Command protocols | slash commands | via routers | via skill routers | via skill routers | via skill routers\* | via skill routers\* | via skill routers\* | **no** |
| Shipped `.claude/agents` personas | yes | yes\* | yes | **no** | not checked | **no** | **no** | **no** |
| Git push gate, after install and configuration | yes | yes | yes | yes | yes | yes | yes | yes |
| Hooks CI, on GitHub | yes | yes | yes | yes | yes | yes | yes | yes |

\* Read from the tool's own documentation on 2026-11-13. Nobody has run this template in that
tool for that cell, so treat it as the vendor's claim, not as a result. Muse Code and
Antigravity have never been run against this template at all.

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
block merges. This template cannot configure an adopter's branch protection;
`bash bin/check-repo-settings.sh` tells you whether yours is on.

On an adapter with no session hooks, the agent follows the instructions without those runtime
checks. The Git gate and CI still work when installed and configured, but neither replaces a
project's own tests or proves that every edit tool is guarded.

## One limit that holds in every tool

The sensitive-file check looks at the file an **edit tool** names. A shell command that writes
a file (`echo ... > .env`, `sed -i`, a script) never passes through it, in any tool here. It
stops the common accident, an agent opening your `.env` to "fix" it. It is not a wall. Keep
your tool's own permission prompts and sandbox on, and keep real secrets out of files an agent
has any reason to open.

## Per-tool notes

### Claude Code
Everything is wired. `CLAUDE.md` imports `AGENTS.md`; four hooks in `.claude/settings.json`;
skills, commands and subagents load natively from `.claude/`.

### Cursor
Guardrail parity through `.cursor/hooks.json`, which calls the same canonical scripts via
`bin/run-claude-hook.sh`. Things to know:

- **No `brain/` injection.** Cursor cannot add prompt context from `beforeSubmitPrompt`. The hook
  is wired and best-effort, but do not count on it - on substantive prompts, ask the agent to
  search the brain, or query it through an MCP server.
- **Skills need a router.** Every canonical skill and command needs a matching file under
  `.cursor/skills/<name>/`, or it is unreachable from Cursor. Hooks CI catches both directions:
  a router pointing at a file that no longer exists, and a skill or command that never got a
  router.
- **Cursor also reads `.claude/`, by its own documentation.** Its setting *Include Third-Party
  Plugins, Skills, and Other Configs* is on by default, and with it Cursor loads the hooks in
  `.claude/settings.json` and the personas in `.claude/agents/`. Not run here. If the Claude
  hooks do load beside `.cursor/hooks.json`, a guardrail runs twice, which is wasteful and not
  unsafe: a block from either one blocks. The routers stay, because nothing here has shown
  Cursor reaching a skill without one.
- **Its MCP file is `.cursor/mcp.json`**, not `.mcp.json`. It is ignored by git here for the
  same reason `.mcp.json` is.

Its hook config declares `failClosed: true` on the block hook, so a check that cannot start
or times out refuses the edit rather than waving it through (from Cursor's documentation; not
run). That covers the adapter failing to run. Once `bin/run-claude-hook.sh` is running it
keeps to the same rule: it allows an edit only when the check finished and said yes (exit 0).
The check's own refusal (exit 2), a check that crashes partway (exit 1, exit 127, a kill) and
a check file that is missing all come back as a refusal, and the last two say that the check
did not run. For a crash the message carries what the check wrote to its error stream; what it
wrote to standard output is dropped. If every edit is refused that way, the check is
what is broken, not your edit: read what the message says the check printed, and restore
`.claude/hooks/block-sensitive-files.sh` from the template if it is gone. Run against stub
checks on 2026-11-13; they are cases in `bin/tests/test-session-start.sh`. This is stricter
than Claude Code, which treats only exit 2 from its own hook as a refusal, so there a crashed
check lets the edit through.
The check itself answers 2 for a payload it cannot read, and 0 for an empty one. The same
holds for Grok Build, whose guide adds that a hook printing plain text and exiting 0 is still
an allow. The session, format and prompt hooks are different: a missing one does nothing, a
crashed one has whatever it printed before it stopped passed on, and either way the session
carries on.

You must trust the workspace for project hooks to load. On Windows, see the Windows section
below before your first edit: a bare `bash` there is WSL's or nothing, and when it is nothing
that fail-closed setting refuses every edit.

### Grok Build
Checked against Grok CLI 1.0.77 on 2026-11-13: its shipped user guide for what it reads, and
`grok inspect` in this repository for what it loaded. Neither is a live session.

- **Skills and commands arrive through `.agents/skills/`.** `grok inspect` resolves `setup`,
  `tdd` and the rest to the routers there, and lists the personas in `.claude/agents/`. Typing
  `/setup` in a session was not tried.
- **Three hooks are wired** in `.grok/hooks/hooks.json` through the shared adapter: session
  start, the sensitive-file check, and format on edit. The check declares `failClosed: true`,
  so a hook that cannot run refuses the edit. Grok's own default is to let it through. The
  adapter's rule described under Cursor applies here too: a check that starts and then
  crashes refuses.
- **Session-start context reaches you, and maybe not the agent.** Grok reads only a top-level
  `systemMessage` from a SessionStart hook and ignores plain output, so the adapter sends
  that. Its guide does not say whether the model receives a `systemMessage` or only you see
  it, and that was not established here.
- **No `brain/` injection.** Grok's guide: an allowing prompt hook's output "is discarded
  rather than added as context". The prompt hook is no longer wired; ask the agent to search
  the brain.
- **The project `.grok/config.toml` cannot switch off Grok's reading of other tools' files.**
  A project config holds `[mcp_servers]`, `[plugins]`, `[permission]` and
  `[mcp] max_output_bytes`, and nothing else. By default Grok also scans `.claude/settings.json`
  and `.cursor/hooks.json`. The first can run each guardrail a second time. The second cannot
  run, and Grok reports its four entries as hook load errors: noise, not a fault. The switch
  is per computer, in `~/.grok/config.toml` (`[compat.claude] hooks = false`,
  `[compat.cursor] hooks = false`). On the one machine this was checked on, the user config
  already had `[compat.claude] hooks = false` and `grok inspect` still listed the Claude
  handlers, so whether that line stops them running is unproven.

Run `/hooks-trust` the first time you open the project or no project hook fires.

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

### Muse Code
Meta's coding agent (the `muse` command). Everything here is from its documentation at
`dev.meta.ai`, read on 2026-11-13. It has not been run against this template.

- It reads the first of `AGENTS.md`, `CLAUDE.md`, `.agents/AGENTS.md` and `.claude/CLAUDE.md`
  it finds at each level, once you trust the workspace. Here that is `AGENTS.md`.
- It scans `.agents/skills`, `.claude/skills` and `.codex/skills`, so the skills are reachable
  both directly and through the routers.
- It has a project hook file, `.muse/hooks.json`, but Meta publishes no schema for it. No hook
  adapter is shipped: one written from third-party descriptions and never run would be a
  guardrail that looks wired and may do nothing. Advisory, plus the Git push gate and CI.

### Antigravity
Google's agent, in the editor and as the `agy` command. Everything here is from its
documentation at `antigravity.google`, read on 2026-11-13. It has not been run against this
template.

- It reads `AGENTS.md` and `GEMINI.md`, both.
- **It cuts any rule file at 24,000 bytes.** This template's `AGENTS.md` ships near 32,000, so
  in Antigravity everything from partway through *External Tools and MCP Servers* onward is
  dropped: Content Rules, Autonomous Housekeeping and Formatting Preferences never load, and
  nothing says so. `bin/check-instruction-budgets.sh` guards Codex's 32,768-byte limit, not
  this one. If Antigravity is your tool, set both `limit` and the `file agents` budget in
  `bin/instruction-budgets.txt` to `24000`, then move explanation out of `AGENTS.md` into
  `docs/` until the check passes.
- It finds skills in `.agents/skills/`, which is where the routers are.
- Its own agents, hooks and MCP servers live in `.agents/agents/`, `.agents/hooks.json` and
  `.agents/mcp_config.json`. It does not read `.claude/`. No hook adapter is shipped, for the
  same reason as Muse Code. Advisory, plus the Git push gate and CI.

### Gemini CLI
`GEMINI.md` points at `AGENTS.md`. Its documentation says it reads `.agents/skills/` too, so the
routers should reach it; not run here. It has hooks of its own (in `.gemini/settings.json`), and
no adapter for them is shipped. Advisory, plus the configured Git push gate and CI.

Check that this is still your tool before investing in it. On 2026-11-13 its README said
individual access had moved to the Antigravity CLI on June 18, 2026, and that Gemini CLI is not
tuned for the Gemini 4 models.

### GitHub Copilot
`.github/copilot-instructions.md` points at `AGENTS.md`. No hooks or skill adapter are shipped
here. Advisory, plus the configured Git push gate and CI.

## Windows

The Cursor and Grok hook configs start each command with `bash`. On Windows that word does
not mean Git Bash: Git for Windows puts only `Git\cmd` on `PATH`, so a bare `bash` is WSL's
launcher or nothing. Cursor's documentation says it runs hook commands through PowerShell
there.

What that does depends on the machine. On the one this was checked on (2026-11-13, Windows
PowerShell 5.1, WSL with Ubuntu), PowerShell found only WSL's `bash`, and the hooks ran inside
Linux: the session block came back and the sensitive-file check refused a `.env` and allowed
an ordinary file, through the slower path that has no `jq`. That is not the same as working:
inside Linux the git state in the session block is whatever Linux's git reports, and the
format hook looks for the edited file by the Windows path the tool sends, does not find it,
and stops without saying so (run under WSL on 2026-11-13 by a reviewer). On a machine with
no WSL distribution the launcher has nothing to start (not run here),
and because both files mark the sensitive-file check `failClosed`, the tool then refuses every
edit. That is the safe direction, and it looks like the template being broken. Either way,
settle it before your first edit.

**Grok Build.** Set the environment variable `GROK_SHELL=bash`: in PowerShell, run
`setx GROK_SHELL bash`, then open a new terminal, because the setting reaches only programs
started after it. Grok's guide names the variable as the setting for hook files shared with
other platforms, and says the command then runs under Git Bash. Nothing in the repository
changes. From the guide; not run here.

**Cursor, when only Windows machines use the repository.** In `.cursor/hooks.json`, change the
first word of each of the four `command` values and nothing else in the file. The first one
becomes:

```json
"command": "C:\\PROGRA~1\\Git\\bin\\bash.exe bin/run-claude-hook.sh cursor session-start",
```

`PROGRA~1` is the short name Windows keeps for `Program Files`. It is there so the command
holds no space and needs no quotes. A quoted path cannot be typed into a JSON string as it
stands, and PowerShell stops with an error on a command that opens with one. Each `\\` is one
backslash, written the way JSON asks. Each form below was handed to a fresh shell as one
command, from this repository's folder, on 2026-11-13:

| The command starts with | PowerShell | `cmd` |
|---|---|---|
| `C:\PROGRA~1\Git\bin\bash.exe` | runs under Git Bash | runs under Git Bash |
| `& 'C:/Program Files/Git/bin/bash.exe'` | runs under Git Bash | fails |
| `"C:\Program Files\Git\bin\bash.exe"` | fails | runs under Git Bash |
| `bash` | runs inside WSL | runs inside WSL |

If Git is installed somewhere else, or `dir /x C:\` shows no `PROGRA~1`, use the second form
with your own path. `where.exe git` prints where Git is; `bash.exe` is in the `bin` folder
beside the `cmd` folder it names. With Git in `D:\Tools\Git`, the first line becomes:

```json
"command": "& 'D:/Tools/Git/bin/bash.exe' bin/run-claude-hook.sh cursor session-start",
```

That form needs PowerShell, which is what Cursor's documentation says it uses.

To see whether a line works before you rely on it, open PowerShell in the project folder and
paste it with something on its input (the hook waits for input otherwise):

```powershell
'{}' | C:\PROGRA~1\Git\bin\bash.exe bin/run-claude-hook.sh cursor session-start
```

Any reply that starts `{"additional_context":"=== SESSION CONTEXT ===` means a Bash answered
and the adapter ran. What follows has `\n` between its lines when `jq` is installed and spaces
when it is not. Git for Windows does not ship `jq`, so spaces are the usual case and are fine.
The reply does not tell you which Bash answered, and WSL's can start the same way and still be
wrong further down (here: an empty `Branch:` and a git error, because Linux's git could not
follow this checkout's Windows paths). To see which Bash it was, run the first word of your
line with `-c 'uname -s'` after it, so `bash -c 'uname -s'` for the bare word and
`C:\PROGRA~1\Git\bin\bash.exe -c 'uname -s'` for the full path: `Linux` is WSL, and anything
else is Git Bash (here: `Linux` for the bare word, `MINGW64_NT-10.0-26200` for the full
path). None of this was run inside Cursor, so step 9 of `SETUP.md` is the check that counts.

**Cursor, when macOS or Linux machines share the repository.** That edit puts a Windows path
in a file everybody runs, and it breaks the hooks for everybody else. Leaving it uncommitted
does not last either: once the push gate is configured, `bin/verify-green.sh` will not record
a proof while a tracked file has unstaged changes. What is left is to make `bash` mean Git
Bash on the Windows machine itself, by putting `C:\Program Files\Git\bin` ahead of
`C:\Windows\System32` in the system `PATH`. That folder holds `bash.exe`, `sh.exe` and
`git.exe` and nothing else. With it first in one PowerShell session's `PATH`, the unedited
`bash bin/run-claude-hook.sh ...` line ran under Git Bash here; the system setting itself was
not changed to test it. The steps are Windows' usual ones and were not walked through here:
search the Start menu for "environment variables", open "Edit the system environment
variables", choose Environment Variables, edit `Path` under System variables, add
`C:\Program Files\Git\bin`, and move it above the `System32` entry. That needs an
administrator account, and Cursor has to be closed and reopened to see it. The cost is that
typing `bash` no longer opens WSL on that machine (`wsl` still does). There is no cleaner
answer today.

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
   tests, and run it in the tool, before claiming support. Reading the tool's documentation
   is where an adapter starts, not where it ends: Grok's session hook shipped here from July
   to November 2026 printing output that Grok 1.0.77 does not read.

Add a column here in the same commit. A tool supported in the repo but missing from this table is
indistinguishable from one that was never supported.
