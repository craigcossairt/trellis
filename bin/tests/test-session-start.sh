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

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
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

# With no argument the installer finds its repo from its OWN location. Run by a
# RELATIVE path with CDPATH exported, `cd bin` resolves through CDPATH and
# echoes the directory, so an unguarded `$(cd "$(dirname ...)" && pwd)` capture
# held two lines, the repo root could not be resolved, and nothing was wired -
# silently, since the installer exits 0 on a repo it cannot find. The case above
# goes through session-start, which passes the repo explicitly.
REL_REPO="$TMP/relative-installer"; new_repo "$REL_REPO"
must mkdir -p "$REL_REPO/bin" "$REL_REPO/.githooks"
must cp "$INSTALLER" "$REL_REPO/bin/install-git-hooks.sh"
: > "$REL_REPO/.githooks/pre-push"
( cd "$REL_REPO" && CDPATH=. bash bin/install-git-hooks.sh >/dev/null 2>&1 )
c_eq "relative + CDPATH=. with no argument still wires its own repo" \
  "$(git -C "$REL_REPO" config --get core.hooksPath || true)" ".githooks"

# Run from inside a git hook (or `git rebase --exec`), the session inherits
# GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE, and `git -C` does not override
# them. Aimed here at a SENTINEL repo: unisolated, the Git State section prints
# the sentinel's branch, and the installer wires the sentinel and leaves the
# session's own repo with no pre-push hook and no message.
SENT="$TMP/env-sentinel"; new_repo "$SENT"
must git -C "$SENT" checkout -q -b sentinel-branch
ENV_REPO="$TMP/env-session"; new_repo "$ENV_REPO"
must git -C "$ENV_REPO" checkout -q -b session-branch
must mkdir -p "$ENV_REPO/bin" "$ENV_REPO/.githooks"
must cp "$INSTALLER" "$ENV_REPO/bin/install-git-hooks.sh"
: > "$ENV_REPO/.githooks/pre-push"
OUT="$(cd "$ENV_REPO" && GIT_DIR="$SENT/.git" GIT_WORK_TREE="$SENT" GIT_INDEX_FILE="$SENT/.git/index" \
  CLAUDE_PROJECT_DIR="$ENV_REPO" bash "$HOOK" 2>&1)"; RC=$?
c_has    "inherited GIT_DIR: Git State names the session's branch" 'Branch: session-branch'
c_hasnot "inherited GIT_DIR: Git State does not name the sentinel's branch" 'sentinel-branch'
c_eq "inherited GIT_DIR: the session's repo is wired" \
  "$(git -C "$ENV_REPO" config --get core.hooksPath || true)" ".githooks"
c_eq "inherited GIT_DIR: the sentinel repo is left alone" \
  "$(git -C "$SENT" config --get core.hooksPath || true)" ""

# The installer isolates itself too, since it is also run on its own.
INST_REPO="$TMP/env-installer"; new_repo "$INST_REPO"
must mkdir -p "$INST_REPO/bin" "$INST_REPO/.githooks"
must cp "$INSTALLER" "$INST_REPO/bin/install-git-hooks.sh"
: > "$INST_REPO/.githooks/pre-push"
( GIT_DIR="$SENT/.git" GIT_WORK_TREE="$SENT" GIT_INDEX_FILE="$SENT/.git/index" \
  bash "$INST_REPO/bin/install-git-hooks.sh" "$INST_REPO" >/dev/null 2>&1 )
c_eq "installer under an inherited GIT_DIR wires the repo it was given" \
  "$(git -C "$INST_REPO" config --get core.hooksPath || true)" ".githooks"
c_eq "installer under an inherited GIT_DIR leaves the sentinel alone" \
  "$(git -C "$SENT" config --get core.hooksPath || true)" ""

# An installer someone deleted during the prune step must not break the session.
NOINST="$TMP/noinstaller"; new_repo "$NOINST"
run "$NOINST"
c_rc "survives a missing installer" 0
c_has "still completes with no installer" '=== END SESSION CONTEXT ==='

echo "== H. the project brain: stale, or its last refresh failed =="
# A scheduled refresh fails where nobody is looking, so this section is the
# alarm. Ages are set with `touch -t` on the stamp file: the hook reads the
# file's modification time, never the date written inside it.
brain_repo() { # $1 name -> a repo with brain/ but no stamp
  local d="$TMP/brain-$1"
  rm -rf "$d"; new_repo "$d"
  must mkdir -p "$d/brain"
  printf '%s' "$d"
}
run_env() { # $1 dir, then VAR=value pairs for the hook's environment
  local dir="$1"; shift
  OUT="$(cd "$dir" && env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK" 2>&1)"
  RC=$?
}

D="$(brain_repo never)"; needdir "$D"; run "$D"
c_hasnot "brain never set up: no brain section" 'Project brain'

D="$(brain_repo fresh)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
run "$D"
c_hasnot "ingested just now: no brain section" 'Project brain'

D="$(brain_repo old)"; needdir "$D"
echo "2020-01-01T00:00:00Z" > "$D/brain/.last-ingest"
must touch -t 202001010000 "$D/brain/.last-ingest"
run "$D"
c_has "ingested years ago: says the brain is stale" '## Project brain is stale'
c_has "stale: shows the recorded ingest date" 'Last ingest: 2020-01-01T00:00:00Z'
c_has "stale: names the refresh command" 'bash brain/scripts/refresh\.sh'
# This text lands in the agent's context at the top of every stale session. An
# imperative there ("schedule that line") reads as an instruction, and creating
# a scheduled job on someone's computer is theirs to say yes to.
c_has "stale: tells the agent to ask before scheduling anything" 'Do not create a scheduled job without asking'
c_hasnot "stale: no bare instruction to schedule it" 'Schedule that line'
c_rc  "stale: still exits 0" 0
c_has "stale: the block still closes" '=== END SESSION CONTEXT ==='

run_env "$D" PROJECT_BRAIN_STALE_DAYS=99999
c_hasnot "threshold raised past the file's age: not stale" 'Project brain'
run_env "$D" PROJECT_BRAIN_STALE_DAYS=0
c_hasnot "threshold 0 turns the staleness line off" 'Project brain'
run_env "$D" PROJECT_BRAIN_STALE_DAYS=soon
c_has "a threshold that is not a number falls back to the default" '## Project brain is stale'
run_env "$D" PROJECT_BRAIN_DISABLE=1
c_hasnot "the brain's kill switch silences the section" 'Project brain'
# 08 and 09 are not octal numbers. Read as one, the threshold is an arithmetic
# error and the staleness line is lost with nothing on screen to say why.
run_env "$D" PROJECT_BRAIN_STALE_DAYS=08
c_has "a threshold written 08 is eight days, and the line still prints" '08? or more days ago|8 or more days ago'
c_hasnot "a threshold written 08 is not an arithmetic error" 'too great for base'

# Both sides of the threshold, an hour or two out. The two ages every other
# case uses (now, and 2020) are both far from it, so an off-by-one-day in the
# comparison passed them all.
hours_ago() { # $1 hours -> a `touch -t` stamp that far back (GNU date, then BSD)
  date -d "$1 hours ago" '+%Y%m%d%H%M' 2>/dev/null || date -v "-${1}H" '+%Y%m%d%H%M'
}
D="$(brain_repo edge)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
must touch -t "$(hours_ago 166)" "$D/brain/.last-ingest"
run "$D"
c_hasnot "ingested 6 days 22 hours ago: not stale yet" 'Project brain'
must touch -t "$(hours_ago 170)" "$D/brain/.last-ingest"
run "$D"
c_has "ingested 7 days 2 hours ago: stale" '## Project brain is stale'

D="$(brain_repo failed)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
printf '2026-03-01 09:00 - the ingest step failed (exit 1).
second line
' > "$D/brain/.refresh-failed"
run "$D"
c_has "failure marker: says the refresh FAILED" '## Project brain: the last refresh FAILED'
c_has "failure marker: prints its first line" 'the ingest step failed'
c_hasnot "failure marker: prints only the first line" 'second line'
c_has "failure marker: the block still closes" '=== END SESSION CONTEXT ==='

# The marker's text goes straight into the session's context, so it is cut to
# printable characters and to 200 of them. A terminal escape or a megabyte of
# output in that file is otherwise the first thing every session reads.
D="$(brain_repo dirty)"; needdir "$D"
echo "2026-01-01T00:00:00Z" > "$D/brain/.last-ingest"
printf '2026-03-01 09:00 - bad \033[31mred\033[0m %s\n' "$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10)$(head -c 300 /dev/zero | tr '\0' 'y')" > "$D/brain/.refresh-failed"
run "$D"
case "$OUT" in
  *"$(printf '\033')"*) bad "failure marker: escape characters are stripped" "$(printf '%s' "$OUT" | cat -v | grep bad)" ;;
  *) ok "failure marker: escape characters are stripped" ;;
esac
MLINE="$(printf '%s\n' "$OUT" | grep '2026-03-01 09:00 - bad')"
if [ "${#MLINE}" -ge 150 ] && [ "${#MLINE}" -le 200 ]; then ok "failure marker: a long line is cut at 200 characters"
else bad "failure marker: a long line is cut at 200 characters" "length ${#MLINE}"; fi

# A marker left behind in a tree whose brain was never set up means nothing:
# refresh.sh cannot have written it there.
D="$(brain_repo orphan)"; needdir "$D"
echo "stray" > "$D/brain/.refresh-failed"
run "$D"
c_hasnot "marker without a set-up brain: no brain section" 'Project brain'

# Both at once: the failure is the cause, so it is the one reported.
D="$(brain_repo both)"; needdir "$D"
echo "2020-01-01T00:00:00Z" > "$D/brain/.last-ingest"
must touch -t 202001010000 "$D/brain/.last-ingest"
echo "2020-01-02 09:00 - the index step failed (exit 3)." > "$D/brain/.refresh-failed"
run "$D"
c_has "stale and failed: reports the failure" 'the last refresh FAILED'
c_hasnot "stale and failed: not also the staleness line" 'Project brain is stale'

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
