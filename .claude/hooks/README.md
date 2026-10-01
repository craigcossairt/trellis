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
  substitution hides it entirely - and `pipefail` fixes only the pipeline.**
  `cmd | while read ...` returns the `while`'s status **without** `set -o pipefail`, so a `cmd`
  that died mid-scan reads as a clean pass; with `pipefail` on (as in `.githooks/pre-push`) the
  pipeline does report the producer's failure, so the warning is conditional, not absolute.
  `while read ...; done < <(cmd)` is the worse one and `pipefail` does **not** help: the
  producer runs in a separate process whose status is never available anywhere, and `$?`
  belongs to the loop. Both turn "the scan broke" into "the scan found nothing". Where the
  producer can fail, run it into a temp file first and check its status, or capture into a
  variable (`out=$(cmd)` sets `$?`) before looping.
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
  suite does not cover this" when it means "the mutation never happened". **Print the diff and
  read it, too** - applying is not the same as applying correctly. A search string that occurs
  twice replaces both, which is a bigger mutation than the one you named and produces a red
  count that looks like broad coverage. Never filter the diff out of the harness's output to
  reduce noise; it is the only thing that shows where the change actually landed.
- **A case whose expected result is "it refused" may not be testing what you think.** A guard
  that refuses on a rule and a guard that refuses because it could not read its input produce
  the same exit code, so breaking the input parsing leaves such a case green. Either pair it
  with a case that can only pass when parsing works (an allowed path, expecting success), or
  assert the refusal MESSAGE, which is where the two differ.
- **Do not begin a comment with the word `shellcheck`.** It is read as a malformed directive
  (SC1072/SC1073) and checking of the rest of the file stops there - so you get FEWER findings,
  which reads as a pass. Hit while writing the suites in `bin/tests/`: the file reported clean,
  and rewording the comment immediately surfaced a real SC2086 further down that had been
  invisible the whole time.
- **`chmod +x` does not reach the index on a Windows checkout.** With `core.fileMode=false`,
  git records the file as `100644` however the working tree looks, and CI's exec-bit step fails
  on a script you can see is executable. Use `git update-index --chmod=+x <file>`.
- **A workflow's `paths:` filter and your required status checks are one rule in two places.**
  If you make a check required in branch protection while its workflow filters paths, any PR
  touching only ignored paths publishes no such check. The requirement never reports, the PR
  waits forever, and with admin enforcement on nobody can override it. There is no error
  anywhere - the PR simply sits. Before making a check required, confirm it runs on every path
  a PR can touch, or add a companion workflow that publishes the same check name for the paths
  the first one ignores.
- **Other harnesses reuse these scripts.** Cursor and Grok Build run them through
  `bin/run-claude-hook.sh`; Codex uses `.codex/hooks.py` to adapt multi-file patches
  and context output. Edit policy here, never a per-harness copy. Test each adapter's
  verdict too: a Windows launcher that turns exit 2 into exit 1 can turn a block
  into a non-blocking hook error.

## Optional hooks (not wired by default)

These ship with their suites but nothing in `.claude/settings.json` runs them. A copy that never
wires them behaves exactly as if they were absent; delete them if you will not use them.

### `heredoc-backslash-warn.mjs` - backslashes in a heredoc fed to an interpreter

`python - <<'EOF'` (or node, bun, perl) hands the heredoc body to the interpreter as SOURCE, so
an escape meant for the output lands as a real CR, NUL or backspace byte, or vanishes. Agents
writing file content this way corrupt it silently, and a written rule against it did not stop
the habit in the project this came from - the warning has to arrive at the moment the command
runs. The hook warns (exit 0, never blocks) when a Bash command feeds a heredoc body holding a
backslash to python/node/bun/perl as program source, and stays silent for heredocs that are data
for a script (`python3 x.py <<EOF`), cat-to-file, bash, `-c` one-liners and here-strings. An
unparseable payload is reported in a `systemMessage`, never silently passed and never blocked.

**Needs node 18 or later on PATH.** Without node, Claude Code shows a non-blocking hook error on
every Bash call, so wire it only where node is installed. To turn it on, add this to the
`PreToolUse` array in `.claude/settings.json`:

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "node \"$CLAUDE_PROJECT_DIR/.claude/hooks/heredoc-backslash-warn.mjs\"",
      "timeout": 10
    }
  ]
}
```

Suite: `node --test .claude/hooks/tests/heredoc-backslash-warn.test.mjs` (runs in hooks CI
whether or not you wire the hook). Claude Code only: the Cursor, Grok and Codex adapters
translate blocks, and a non-blocking warning has no equivalent there yet.

### Shared main checkout tooling - `.githooks/reference-transaction`, `bin/check-main-checkouts.sh`

Not Claude Code hooks, but the same opt-in shape. Once several sessions share one machine, the
main checkout stays parked on the default branch (`docs/growing-into-a-workspace.md`). Mark it
in its own local config - never tracked, so no clone inherits it:

```bash
git config --local project.sharedCheckout true
git config --local project.defaultBranch trunk   # only if the default is not "main"
```

Then the git `reference-transaction` hook (live wherever `bin/install-git-hooks.sh` has set
`core.hooksPath=.githooks`) refuses any HEAD move off the default branch in that checkout, from
any caller, while letting `git worktree add`, commits, pulls and fetches through; and
`session-start.sh` runs `bin/check-main-checkouts.sh` to report the checkout if it is off the
default branch, dirty, or carries a repo-local git identity. Unmarked, the git hook exits 0 on
every transaction and session-start prints nothing new. Bypass for one command:
`PROJECT_ALLOW_CHECKOUT=1 git switch <branch>`. Suites: `bin/tests/test-reference-transaction.sh`,
`bin/tests/test-check-main-checkouts.sh`, `bin/tests/test-session-start-main-checkout.sh`.
