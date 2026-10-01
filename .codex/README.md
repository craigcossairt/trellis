# Codex adapter

Codex reads `AGENTS.md` natively. Skills are routed through `.agents/skills/`.
This directory supplies command hooks; the policy and formatting commands remain
in the canonical `.claude/hooks/` scripts.

## Requirements and activation

Install Python 3.10 or newer, Git, and Bash. On Windows, install Git for Windows
and make `python` available on PATH. The adapter finds Git Bash from the Git
installation; it does not use the WSL `bash` stub. For a nonstandard installation,
set the device-local `TRELLIS_BASH` environment variable to the Bash executable.

1. Use a Codex release with command hooks and `commandWindows` support.
2. Trust the project in Codex. Project-local config and hooks are skipped in an
   untrusted project.
3. Open `/hooks` in the Codex CLI, review the four hook definitions, and trust
   them. Changed definitions need review again. Do not disable sandboxing or use
   a trust-bypass flag for routine setup.
4. Run `bash bin/install-git-hooks.sh` independently of the session hook, then
   verify `git config --get core.hooksPath` points at this project's `.githooks`.
   If an existing hook manager is present, follow the installer's message.
5. Run `python3 bin/validate-codex.py` and the checks in `SETUP.md`.
   A static check cannot prove that the project or hook definitions were trusted.

Python must be available to the process running Codex. If the interpreter itself
cannot start, Codex may report a non-blocking launch error; the adapter cannot
produce a denial before it runs. Complete the live activation check in `SETUP.md`.

The Windows command uses a small Python bootstrap to find the Git root and run
the adapter. It returns a structured denial for failed file checks because an
outer PowerShell can turn a native exit 2 into a non-blocking exit 1. The bootstrap
is inline so a missing adapter file can still be reported. It contains no shell
variables and is tested through both PowerShell and cmd. Unix commands resolve
the same root in the shell. Both work from subdirectories and paths with spaces.

## Events and coverage

| Event | Behavior |
|---|---|
| SessionStart | Loads Git state and references; invokes the shared Git-hook installer |
| PreToolUse (`apply_patch`) | Checks every add, update, delete, and rename path using the shared sensitive-file policy |
| PostToolUse (`apply_patch`) | Formats surviving files with the shared formatter script |
| UserPromptSubmit | Loads optional `brain/` context; does nothing when the brain is absent or disabled |

Codex sends patch text in `tool_input.command`, rather than a single file path.
`hooks.py` translates it into one canonical hook payload per touched path.
Renames check both source and destination. The adapter trims header whitespace
as Codex does, checks both symlink spellings, and rejects ambiguous Windows
filenames such as trailing dots and alternate data streams. Malformed or unknown patch input,
missing policy scripts, and failed policy execution block the edit.

The patch is split on newlines only, as Codex splits it. Python's
`splitlines()` also breaks on U+2028, U+0085 and similar characters, which let
one header read as two lines here while Codex read a single path; a header
containing any of them is refused.

The two context hooks never block. Exit 2 on `UserPromptSubmit` blocks the
user's prompt, so a missing adapter, a missing Git root, a slow brain or a
crashed context script is reported as a `NOTE:` in the session's context and
the hook exits 0, on both the POSIX and the Windows command. Each launcher's
timeout outlasts the script it runs, so the adapter, not the launcher's own
timeout, decides the result.

These edit hooks cover `apply_patch`. Shell commands and other tools can also
write files and are outside this path check. Keep Codex's sandbox and permission
controls enabled, and use the Git push gate and CI for verification. Do not
describe these hooks as a complete security boundary.

The optional brain may be deleted. If you remove a required canonical hook,
remove the corresponding configuration too and update your adapter deliberately.
Delete `.codex/` to remove this entire optional hook adapter.

## Verification

`python3 bin/tests/test_codex_hooks.py` drives the adapter with Codex-shaped
payloads and the real shared file policy. Tests use temporary fixtures and
exercise ordinary edits, protected files, mixed patches, renames, malformed
inputs, nested directories, missing scripts, context output, and formatter
dispatch. They do not assert that a user's interactive session has trusted hooks.

Reference: [OpenAI hooks documentation](https://learn.chatgpt.com/docs/hooks).
