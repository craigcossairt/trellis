#!/usr/bin/env bash
# =============================================================================
# claim-branch.sh - has someone else already worked this branch?
# =============================================================================
# `.claude/commands/worktree.md` stops two sessions sharing a CHECKOUT. Nothing
# stops them sharing a BRANCH: both fetch it clean, both commit, and the second
# push either clobbers or leaves the branch 1-ahead/1-behind to untangle by hand.
#
# WHAT THIS DETECTS: commits ALREADY PUSHED to the branch under a DIFFERENT git
# author email. That is the teammate case, and it is worth checking before you
# start on a branch you did not create.
#
# WHAT IT CANNOT DETECT - do not rely on it for either:
#   - Two agent sessions running under YOUR identity. They stamp the same
#     user.email, so the other session's commits are indistinguishable from
#     your own and the branch reports free. Read the exit-0 line literally:
#     "all yours" means "all under your email", not "all written by you".
#   - Work nobody has pushed yet. A branch absent from the remote is free for
#     every caller at once. This reads the remote; it reserves nothing.
# Closing either gap needs a lease published where both sessions can see it,
# which this script deliberately does not do.
#
# A clean fast-forward is NOT permission. That is what a collision looks like
# from the inside, which is why "it merged fine" is not evidence of anything.
#
#   bin/claim-branch.sh <branch>            # report; exit 1 if claimed
#   bin/claim-branch.sh <branch> --quiet    # exit code only
#
# Exit codes are the contract:
#   0  free            - no remote branch, or every commit on it is under your
#                        own user.email (see the limits above)
#   1  CLAIMED         - remote branch carries commits by another author
#   2  could not tell  - no network, bad args, not a git repo
#
# 2 is deliberately NOT folded into either 0 or 1. "I could not reach the
# remote" is not "nobody is there" - the same mistake as `|| true` on a grep, or
# a scan that cannot run reading as clean. A caller that treats 2 as free has
# reintroduced the bug this script exists to prevent.
# =============================================================================
set -uo pipefail

QUIET=0
BRANCH=""
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *)
      if [ -z "$BRANCH" ]; then
        BRANCH="$arg"
      else
        echo "too many arguments" >&2; exit 2
      fi
      ;;
  esac
done

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

[ -n "$BRANCH" ] || { echo "usage: claim-branch.sh <branch> [--quiet]" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository" >&2; exit 2; }

# Who am I? The email git will actually stamp on a commit is the only identity
# that distinguishes sessions here.
ME_NAME="$(git config user.name 2>/dev/null || true)"
ME_EMAIL="$(git config user.email 2>/dev/null || true)"
[ -n "$ME_EMAIL" ] || {
  echo "git user.email is unset - cannot tell your commits from anyone else's" >&2
  exit 2
}

# The base branch to scope the range against. Do not hardcode 'main': a repo
# started from this template may use master, trunk, or anything else. Ask the
# remote what its HEAD points at, and fall back only if it has not been set.
BASE=""
if ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
  BASE="${ref#refs/remotes/}"
fi
if [ -z "$BASE" ]; then
  for candidate in origin/main origin/master; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then BASE="$candidate"; break; fi
  done
fi
[ -n "$BASE" ] || {
  echo "cannot determine the default branch - run 'git remote set-head origin -a'" >&2
  exit 2
}

# Does the branch exist on the remote? ls-remote exits 0 with EMPTY output when
# the ref is absent and non-zero when it could not ask. Those are different
# answers and must never share a branch of this `case`.
rc=0
remote_line="$(git ls-remote --exit-code --heads origin "$BRANCH" 2>/dev/null)" || rc=$?
case "$rc" in
  0) : ;;                                                # exists
  2) say "free: no remote branch '$BRANCH'"; exit 0 ;;    # --exit-code: no match
  *) echo "could not reach origin (git ls-remote exit $rc)" >&2; exit 2 ;;
esac

REMOTE_SHA="${remote_line%%$'\t'*}"

# Fetch the branch's FULL history, not a shallow slice. A shallow `--depth=N` is
# unsafe here: a branch with N recent commits of yours can still carry an OLDER
# commit by someone else, and the shallow fetch hides it while `git log` still
# succeeds. That reports 'free' on a claimed branch, which is the single answer
# this script must never get wrong. Correctness beats the few hundred ms.
if ! git fetch --quiet --no-tags origin "$BRANCH" 2>/dev/null; then
  echo "could not fetch origin/$BRANCH" >&2
  exit 2
fi

# Attribute against what was JUST fetched, not the SHA read from ls-remote
# earlier. The branch can advance between the two calls, and judging a stale SHA
# would miss exactly the commit someone else has only now pushed.
if ! FETCHED_SHA="$(git rev-parse FETCH_HEAD 2>/dev/null)"; then
  echo "could not resolve FETCH_HEAD for $BRANCH" >&2
  exit 2
fi
if [ "$FETCHED_SHA" != "$REMOTE_SHA" ]; then
  say "note: '$BRANCH' moved between discovery and fetch; judging the newer $FETCHED_SHA"
fi

# Commits on the branch that are not on the base branch - the work someone has
# already done here. Scope against the base rather than your local HEAD: you may
# not have this branch at all yet. The base must be present for the range to
# mean anything; an absent one would make every commit look novel.
if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
  echo "$BASE not in this checkout - cannot scope the range" >&2
  exit 2
fi
if ! authors="$(git log --format='%ae|%an|%h|%s' "$BASE..$FETCHED_SHA" 2>/dev/null)"; then
  echo "could not read history for $BRANCH" >&2
  exit 2
fi

if [ -z "$authors" ]; then
  say "free: '$BRANCH' exists but has no commits beyond $BASE"
  exit 0
fi

others="$(printf '%s\n' "$authors" | awk -F'|' -v me="$ME_EMAIL" '$1 != me')"

if [ -z "$others" ]; then
  n=$(printf '%s\n' "$authors" | grep -c . || true)
  say "free: '$BRANCH' has $n commit(s), all yours ($ME_EMAIL)"
  exit 0
fi

say "CLAIMED: '$BRANCH' carries commits by someone else"
say ""
printf '%s\n' "$others" | awk -F'|' '{printf "    %s  %s  <%s>  %s\n", $3, $2, $1, $4}' \
  | while IFS= read -r l; do say "$l"; done
say ""
say "  you are: $ME_NAME <$ME_EMAIL>"
say ""
say "  Do not push over it. Either pick a different branch, or coordinate -"
say "  another session may still be mid-task. If you have already fetched it,"
say "  'git log origin/$BRANCH' shows what they have done."
exit 1
