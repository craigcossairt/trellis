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
- **A session hook that overruns its time budget is killed and its output is DISCARDED.** Not
  truncated - discarded, with no error. Every warning the hook meant to surface vanishes, and
  the session looks clean precisely when it is not. Keep session hooks fast, measure them
  rather than assuming, and be careful with per-file subprocesses in a loop: that is what turns
  a fast hook into a silent one as a repo grows.
- **A pipeline hides the exit status of everything but its last command, and process
  substitution hides it entirely.** `cmd | while read ...` returns the `while`'s status, so a
  `cmd` that died mid-scan reads as a clean pass; `while read ...; done < <(cmd)` is worse,
  because `cmd`'s status is never available at all - `set -o pipefail` does not cover it and
  `$?` belongs to the loop. Both are ordinary shell, and both turn "the scan broke" into "the
  scan found nothing". Where the producer can fail, run it into a temp file first and check its
  status, or capture into a variable (`out=$(cmd)` sets `$?`) before looping.
- **The scripts have their own CI.** `.github/workflows/hooks-ci.yml` gates every `*.sh` and
  `.githooks/*` file: CRLF check, `bash -n`, shellcheck, exec bits (git skips a non-executable
  hook without a word), and the behavioral suites in `bin/tests/`.
- **A test suite that CI never invokes is not coverage.** The claim-branch suite shipped with a
  header describing what it proved and sat unrun for a month, because nothing in the workflow
  called it - a shape worth watching for, since the docs read exactly the same either way.
  Every suite gets its own NAMED step, carrying the mutation ledger that shows it asserts
  something: break the thing under test, predict which case labels go red, then read which ones
  actually did. Confirm the mutation changed the file before believing its result - a pattern
  that no longer matches leaves the mutant byte-identical, and that all-green run reads as "the
  suite does not cover this" when it means "the mutation never happened".
- **A workflow's `paths:` filter and your required status checks are one rule in two places.**
  If you make a check required in branch protection while its workflow filters paths, any PR
  touching only ignored paths publishes no such check. The requirement never reports, the PR
  waits forever, and with admin enforcement on nobody can override it. There is no error
  anywhere - the PR simply sits. Before making a check required, confirm it runs on every path
  a PR can touch, or add a companion workflow that publishes the same check name for the paths
  the first one ignores.
- **Other harnesses reuse these scripts.** Cursor and Grok Build run them through
  `bin/run-claude-hook.sh` - edit the canonical script here, never a per-harness copy.
