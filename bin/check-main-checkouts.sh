#!/usr/bin/env bash
# =============================================================================
# check-main-checkouts.sh - is each shared MAIN checkout still parked?
# =============================================================================
# Optional. Once several agent sessions work one machine, the main checkout of
# each repo is shared by all of them and stays on the default branch, clean;
# branch work goes in linked worktrees (docs/growing-into-a-workspace.md).
#
# A guard that blocks `git switch` on the agent's tool-call command line only
# sees commands it can read. An agent that writes its git steps into a script
# file and runs it gets past such a guard, and can leave the shared checkout on
# its own branch, full of dirty files, with a repo-local git identity it set
# along the way. Nothing in the guard's view changed, so nothing reported it.
#
# This checks the END STATE instead of the command, so it catches the result
# however it happened: a script, a terminal, another harness. It prevents
# nothing; docs/growing-into-a-workspace.md says why there is no git hook
# that blocks the move instead. It reports, per checkout:
#   - HEAD not on the default branch (another branch, or detached)
#   - any uncommitted or untracked path (ignored files are fine)
#   - a repo-local user.email or user.name. Agents run as the owner and pick up
#     the global identity; a local one in a shared checkout means something
#     changed it. A project that genuinely needs its own identity can say so in
#     GLOBAL config with an includeIf block, which this does not flag.
#
# The default branch is read per checkout from `project.defaultBranch` in its
# local config, and is `main` when unset.
#
# Usage: check-main-checkouts.sh <main-checkout-dir>...
#
# .claude/hooks/session-start.sh runs it on the session's own main checkout,
# but only once that checkout is marked: git config --local project.sharedCheckout true
#
# Exit codes, three states, never two:
#   0  every checkout is parked; prints nothing
#   1  at least one problem, one line each on stdout
#   2  at least one checkout could not be checked. Outranks 1, and every
#      finding still prints: an unreadable checkout must not read as parked,
#      and a problem in one checkout must not hide an unreadable other.
#
# Read-only: `git --no-optional-locks status` skips the index refresh write, so
# the check never takes a lock another session may hold.
# =============================================================================
set -uo pipefail

# `git -C` does not override an inherited GIT_DIR, GIT_WORK_TREE or
# GIT_INDEX_FILE. Run from a git hook or `git rebase --exec`, every read below
# would describe the repo those name, under the name of the checkout asked
# about: a false "parked". Drop every repo-local variable git itself lists.
for v in $(git rev-parse --local-env-vars 2>/dev/null); do unset "$v"; done

LIST_MAX=5

if [ "$#" -eq 0 ]; then
  echo "usage: check-main-checkouts.sh <main-checkout-dir>..." >&2
  exit 2
fi

found=0
unknown=0

cannot() { echo "cannot check $1: $2"; unknown=1; }
problem() { echo "main checkout $1: $2"; found=1; }

# local_identity <dir> <key> - report a repo-local value. git config --get
# exits 1 for "not set"; anything else is a broken read, never clean.
local_identity() {
  local dir="$1" key="$2" val rc=0
  val=$(git -C "$dir" config --local --get "$key" 2>&1) || rc=$?
  case "$rc" in
    0) problem "$dir" "repo-local $key=$val (identity belongs in global config - an includeIf block there can give one repo its own; remove with: git -C \"$dir\" config --local --unset $key)" ;;
    1) ;;
    *) cannot "$dir" "git config --local --get $key failed (exit $rc): $val" ;;
  esac
}

check_one() {
  local dir="$1" branch rc status count listed expected gd common

  if [ ! -d "$dir" ]; then
    cannot "$dir" "no such directory"; return
  fi
  # No .git of either shape means this is not the top of a checkout. Checked
  # first so a plain directory inside some other repo is not judged as that
  # repo under this name.
  if [ ! -e "$dir/.git" ]; then
    cannot "$dir" "not a git checkout (no .git)"; return
  fi

  # An unparseable config breaks every later git call; name it here, once.
  rc=0; git -C "$dir" config --local --list >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    cannot "$dir" "its git config cannot be read (exit $rc)"; return
  fi

  # Linked worktree or main checkout? Not by the shape of .git: a linked
  # worktree has a .git FILE, but so does a main checkout made with
  # `git init --separate-git-dir`. A linked worktree is the one whose git dir
  # differs from the common dir. Branch work in a linked worktree is the point
  # of the rule, so judging one here would be a false alarm.
  rc=0; gd=$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2>&1) || rc=$?
  [ "$rc" -eq 0 ] && { common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>&1) || rc=$?; }
  if [ "$rc" -ne 0 ]; then
    cannot "$dir" "git rev-parse failed (exit $rc)"; return
  fi
  if [ "$gd" != "$common" ]; then
    cannot "$dir" "not a main checkout (it is a linked worktree)"; return
  fi

  rc=0; expected=$(git -C "$dir" config --local --get project.defaultBranch 2>&1) || rc=$?
  case "$rc" in
    0) [ -n "$expected" ] || expected=main ;;
    1) expected=main ;;
    *) cannot "$dir" "git config --local --get project.defaultBranch failed (exit $rc): $expected"; return ;;
  esac

  local_identity "$dir" user.email
  local_identity "$dir" user.name

  # The full ref, not --short: with a tag of the same name, --short answers
  # `heads/main` to avoid ambiguity, and a parked checkout would read as off.
  rc=0; branch=$(git -C "$dir" symbolic-ref -q HEAD 2>&1) || rc=$?
  case "$rc" in
    0) [ "$branch" = "refs/heads/$expected" ] ||
         problem "$dir" "on branch '${branch#refs/heads/}', not $expected (check nobody is mid-work there, then: git -C \"$dir\" switch $expected)" ;;
    1) problem "$dir" "HEAD is detached at $(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo '?'), not on $expected" ;;
    *) cannot "$dir" "git symbolic-ref HEAD failed (exit $rc): $branch" ;;
  esac

  rc=0
  status=$(git --no-optional-locks -C "$dir" status --porcelain --untracked-files=all 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    cannot "$dir" "git status failed (exit $rc): $(printf '%s' "$status" | head -1)"; return
  fi
  if [ -n "$status" ]; then
    count=$(printf '%s\n' "$status" | wc -l | tr -d ' ')
    listed=$(printf '%s\n' "$status" | head -n "$LIST_MAX" | sed 's/^...//' | tr '\n' ' ')
    if [ "$count" -gt "$LIST_MAX" ]; then
      listed="${listed}and $((count - LIST_MAX)) more"
    fi
    problem "$dir" "$count uncommitted or untracked path(s): $listed"
  fi
}

for d in "$@"; do
  check_one "$d"
done

[ "$unknown" -eq 1 ] && exit 2
[ "$found" -eq 1 ] && exit 1
exit 0
