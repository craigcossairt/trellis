#!/usr/bin/env bash
# =============================================================================
# test-session-start.sh - behavioral tests for .claude/hooks/session-start.sh
# =============================================================================
# This hook looks like a pile of echoes, which is why it went unpinned. It is
# not: it picks its own root, branches on whether that root is a git repo, caps
# a list with arithmetic, and shells out to the installer that wires the real
# git pre-push hook. Each of those can break quietly, and the failure mode of a
# SessionStart hook is silence - you get a session with no context and nothing
# says so.
#
# What is pinned, and why each one matters:
#
#   1. It always exits 0. A session hook that fails takes the session's opening
#      context with it.
#   2. Both markers print, always, in and out of a git repo. They are how a
#      reader (and the model) knows the block is complete rather than truncated.
#   3. It honours CLAUDE_PROJECT_DIR and falls back to the working directory.
#      Getting this wrong reports another repo's state, which is worse than
#      reporting none - it is confidently wrong.
#   4. `.git` as a FILE is still a git repo. That is a linked worktree, which is
#      how this template tells you to do all branch work, so dropping that check
#      would blind the hook in the exact place it is most used.
#   5. The 15-line cap and its "... and N more" arithmetic, on both sides of the
#      boundary. An off-by-one here is invisible in ordinary use.
#   6. It self-heals the git hook wiring, and survives that installer being
#      absent.
#
# Hermetic: temp git repos, no network, global git config neutralised.
#
# Run:  bash bin/tests/test-session-start.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/session-start.sh"
INSTALLER="$ROOT/bin/install-git-hooks.sh"
for f in "$HOOK" "$INSTALLER"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$(printf '%s' "$2" | head -4 | tr '\n' '|')"; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }
# A fixture that yields an empty path must abort, not silently make `cd ""` a
# no-op that runs the hook against this repo. That is how the first draft of the
# cap cases "passed" against the wrong tree.
needdir() { [ -n "${1:-}" ] && [ -d "$1" ] || { echo "FIXTURE FAILED: empty or missing fixture dir" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t sesstart)"
trap 'rm -rf "$TMP"' EXIT

new_repo() { # $1 dir -> an initialised repo with one commit
  must git init -q "$1"
  must git -C "$1" config user.email 'me@example.com'
  must git -C "$1" config user.name 'Me'
  must git -C "$1" config commit.gpgsign false
  must git -C "$1" config core.autocrlf false
  echo seed > "$1/seed.txt"
  must git -C "$1" add seed.txt
  must git -C "$1" commit -q -m 'seed commit'
}

OUT=""; RC=0
run() { # $1 dir to run in, $2 optional CLAUDE_PROJECT_DIR ("-" for unset)
  local dir="$1" proj="${2:--}"
  if [ "$proj" = "-" ]; then
    OUT="$(cd "$dir" && env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>&1)"
  else
    OUT="$(cd "$dir" && CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" 2>&1)"
  fi
  RC=$?
}

# Assertion helpers, not `cond && ok || bad`: in that construct `bad` also runs
# when `ok` itself fails, so a bookkeeping slip turns into a phantom failure.
# SC2015 flags exactly that, and is right to.
#
# (Note the wording above: a comment whose first word is the linter's own name
# is read as a malformed directive, and it stops checking the rest of the file
# from that line on - fewer findings, which reads as a pass. Start such a line
# with any other word.)
has()    { printf '%s' "$OUT" | grep -qE "$1"; }
hasnot() { ! printf '%s' "$OUT" | grep -qE "$1"; }
c_has()    { if has "$2";    then ok "$1"; else bad "$1" "$OUT"; fi; }
c_hasnot() { if hasnot "$2"; then ok "$1"; else bad "$1" "$OUT"; fi; }
c_rc()     { if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "exit $RC"; fi; }
c_eq()     { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi; }

# --- Fixtures ----------------------------------------------------------------
REPO="$TMP/repo";      new_repo "$REPO"
must git -C "$REPO" checkout -q -b feature/widget
EMPTY="$TMP/plain";    mkdir -p "$EMPTY"       # not a git repo at all
OTHER="$TMP/other";    new_repo "$OTHER"
must git -C "$OTHER" checkout -q -b other/branch

echo "== A. it always completes =="
run "$REPO"
c_rc "exits 0 inside a git repo" 0
run "$EMPTY"
c_rc "exits 0 outside a git repo" 0

echo "== B. the block is always complete =="
run "$REPO"
c_has "prints the opening marker" '=== SESSION CONTEXT ==='
c_has "prints the closing marker" '=== END SESSION CONTEXT ==='
c_has "prints Quick References" 'Quick References'
run "$EMPTY"
c_has "opening marker outside a repo" '=== SESSION CONTEXT ==='
c_has "closing marker outside a repo" '=== END SESSION CONTEXT ==='
c_has "Quick References outside a repo" 'Quick References'
c_hasnot "no Git State section outside a repo" '## Git State'

echo "== C. git state =="
run "$REPO"
c_has "reports the current branch" 'Branch: feature/widget'
c_has "reports recent commits" 'seed commit'
c_hasnot "clean tree shows no changes block" 'Uncommitted changes'

echo "== D. it reads the root it was told to read =="
# The dangerous failure is not "no output" - it is reporting a DIFFERENT repo's
# branch, which reads as correct. So both directions are asserted by name.
run "$EMPTY" "$REPO"
c_has "CLAUDE_PROJECT_DIR wins over the working dir" 'Branch: feature/widget'
run "$OTHER" "$REPO"
c_has "reports the told root, not the cwd repo" 'Branch: feature/widget'
c_hasnot "does not leak the cwd repo's branch" 'Branch: other/branch'
run "$OTHER"
c_has "falls back to the working dir when unset" 'Branch: other/branch'

echo "== E. a linked worktree is still a git repo =="
# In a worktree, .git is a FILE containing a gitdir: pointer, not a directory.
# All branch work in this template happens in worktrees, so losing this check
# would blind the hook exactly where it is used most.
WT="$TMP/wt"
must git -C "$REPO" worktree add -q -b wt/branch "$WT"
[ -f "$WT/.git" ] || { echo "FIXTURE FAILED: expected .git to be a file in a worktree" >&2; exit 1; }
run "$WT"
c_has "worktree gets a Git State section" '## Git State'
c_has "worktree reports its own branch" 'Branch: wt/branch'

echo "== F. the uncommitted-changes cap =="
# Both sides of the boundary. An off-by-one here never shows up in normal use.
cap_repo() { # $1 count -> fresh repo with N untracked files at the root
  # Two statements on purpose: `local a="$1" b="$a"` does not reliably see `a`
  # in the same declaration, and under `set -u` that aborts the function and
  # returns an empty path - which made `run ""` fall back to the real repo and
  # assert against this checkout instead of the fixture.
  local n="$1"
  local d="$TMP/cap$n"
  rm -rf "$d"; new_repo "$d"
  local i=1
  while [ "$i" -le "$n" ]; do : > "$d/file$i.txt"; i=$((i + 1)); done
  printf '%s' "$d"
}
D="$(cap_repo 3)"; needdir "$D"; run "$D"
c_has "3 changes: shows the changes block" 'Uncommitted changes'
c_hasnot "3 changes: no overflow line" 'more files'

D="$(cap_repo 15)"; needdir "$D"; run "$D"
c_hasnot "15 changes: exactly at the cap, no overflow line" 'more files'
c_eq "15 changes: all 15 listed" "$(printf '%s' "$OUT" | grep -cE '^\?\? file[0-9]+\.txt$')" 15

D="$(cap_repo 16)"; needdir "$D"; run "$D"
c_has "16 changes: reports exactly 1 more" 'and 1 more'
c_eq "16 changes: list is capped at 15" "$(printf '%s' "$OUT" | grep -cE '^\?\? file[0-9]+\.txt$')" 15

D="$(cap_repo 20)"; needdir "$D"; run "$D"
c_has "20 changes: reports exactly 5 more" 'and 5 more'

echo "== G. it self-heals the git hook wiring =="
SH_REPO="$TMP/selfheal"; new_repo "$SH_REPO"
must mkdir -p "$SH_REPO/bin" "$SH_REPO/.githooks"
must cp "$INSTALLER" "$SH_REPO/bin/install-git-hooks.sh"
: > "$SH_REPO/.githooks/pre-push"
[ -z "$(git -C "$SH_REPO" config --get core.hooksPath || true)" ] \
  || { echo "FIXTURE FAILED: core.hooksPath was already set" >&2; exit 1; }
run "$SH_REPO"
c_eq "wires core.hooksPath when unset" "$(git -C "$SH_REPO" config --get core.hooksPath || true)" ".githooks"

# An installer someone deleted during the prune step must not break the session.
NOINST="$TMP/noinstaller"; new_repo "$NOINST"
run "$NOINST"
c_rc "survives a missing installer" 0
c_has "still completes with no installer" '=== END SESSION CONTEXT ==='

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
