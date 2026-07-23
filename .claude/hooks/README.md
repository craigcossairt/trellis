# Hook-writing notes

Lessons already baked into these scripts - keep them in mind when adding hooks:

- **The payload arrives on stdin as JSON.** `$TOOL_INPUT` is not populated. Reading it yields
  an empty string and the hook silently no-ops on every call - see `hook-file-path.sh` for the
  history of that bug.
- **A hook that no-ops is indistinguishable from a hook that passes.** Verify every guardrail
  with a deliberate violation (SETUP.md § Sanity check), never by absence of complaints.
- **Never `grep -P`.** BSD grep (macOS) has no `-P`, and GNU grep's `-P` dies on non-UTF-8
  locales (seen in Git Bash on Windows). Use `jq`, or POSIX `sed` as the fallback.
- **Blockers fail closed; helpers fail open.** `block-sensitive-files.sh` blocks when it cannot
  parse a path; `format-on-edit.sh` just skips. Match the failure mode to the stakes.
- **Windows:** a bare `bash` can resolve to WSL, where HOME and every path are wrong - harness
  configs should name Git Bash's full path (see `.grok/hooks/hooks.json`). Shell scripts must
  check out with LF (`.gitattributes` forces it).
- **The scripts have their own CI.** `.github/workflows/hooks-ci.yml` gates every `*.sh` and
  `.githooks/*` file: CRLF check, `bash -n`, shellcheck, and exec bits - git skips a
  non-executable hook without a word.
- **Other harnesses reuse these scripts.** Cursor and Grok Build run them through
  `bin/run-claude-hook.sh` - edit the canonical script here, never a per-harness copy.
