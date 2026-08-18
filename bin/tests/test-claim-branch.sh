#!/usr/bin/env bash
# =============================================================================
# test-claim-branch.sh - hermetic tests for bin/claim-branch.sh
# =============================================================================
# Builds a throwaway bare repo to play origin, so nothing here touches a real
# remote and the suite is safe to run anywhere.
#
# Half of these cases assert that exit 2 (could not tell) never collapses to
# exit 0 (free). That is the property the script exists for: "I could not check"
# reading as "nobody is there" is the bug, and it is the one a careless refactor
# reintroduces first.
#
# Run:  bash bin/tests/test-claim-branch.sh
# =============================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claim-branch.sh"
[ -f "$SCRIPT" ] || { echo "cannot find claim-branch.sh next to this test" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# expect <label> <expected-exit> <args...>
expect() {
  local label="$1" want="$2"; shift 2
  local out rc=0
  out="$(bash "$SCRIPT" "$@" 2>&1)" || rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$label"; else bad "$label" "wanted exit $want, got $rc: $out"; fi
}

SANDBOX="$(mktemp -d 2>/dev/null || mktemp -d -t claimbranch)"
trap 'rm -rf "$SANDBOX"' EXIT

git init --quiet --bare "$SANDBOX/origin.git"
git init --quiet "$SANDBOX/work"
cd "$SANDBOX/work" || exit 1
git config user.email "me@example.com"
git config user.name  "Me"
git config commit.gpgsign false
git config core.autocrlf false
git remote add origin "$SANDBOX/origin.git"

echo base > f.txt
git add f.txt
git commit --quiet -m base
git branch -M main
git push --quiet -u origin main
git remote set-head origin -a >/dev/null 2>&1

# A branch carrying someone else's commit.
git switch --quiet -c feature/theirs
echo x >> f.txt
git -c user.email="other@example.com" -c user.name="Other Dev" commit --quiet -am "their work"
git push --quiet -u origin feature/theirs

# A branch carrying only mine.
git switch --quiet main
git switch --quiet -c feature/mine
echo y >> f.txt
git commit --quiet -am "my work"
git push --quiet -u origin feature/mine

# A branch with mine on top of theirs - the shallow-fetch trap. An older commit
# by someone else must still be found under newer commits of yours.
git switch --quiet feature/theirs
git switch --quiet -c feature/mixed
echo z >> f.txt
git commit --quiet -am "my later work"
git push --quiet -u origin feature/mixed

git switch --quiet main

echo "claim-branch.sh"

# --- free -----------------------------------------------------------------
expect "absent remote branch is free"            0 no-such-branch
expect "branch of only my commits is free"       0 feature/mine
expect "the base branch itself is free"          0 main

# --- claimed --------------------------------------------------------------
expect "another author's branch is CLAIMED"      1 feature/theirs
expect "my commits ON TOP of theirs is CLAIMED"  1 feature/mixed

# --- could not tell (must never read as free) -----------------------------
expect "no argument is 2, not 0"                 2
expect "unknown flag is 2, not 0"                2 feature/mine --bogus
expect "too many arguments is 2, not 0"          2 feature/mine extra

rc=0; out="$(cd "$SANDBOX" && bash "$SCRIPT" feature/mine 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then ok "outside a git repo is 2, not 0"
else bad "outside a git repo is 2, not 0" "got $rc: $out"; fi

# Unsetting only the LOCAL user.email is not enough: git falls back to the
# global one, the script gets a real (wrong) identity, and the case passes or
# fails for a reason that has nothing to do with what it claims to test. The
# global and system files have to be neutralised too.
rc=0
git config --local --unset user.email >/dev/null 2>&1 || true
out="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$SCRIPT" feature/mine 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then ok "unset user.email is 2, not 0"
else bad "unset user.email is 2, not 0" "got $rc: $out"; fi
git config user.email "me@example.com"

# --- reporting ------------------------------------------------------------
out="$(bash "$SCRIPT" feature/theirs 2>&1)" || true
case "$out" in
  *other@example.com*) ok "CLAIMED output names the other author" ;;
  *) bad "CLAIMED output names the other author" "got: $out" ;;
esac

out="$(bash "$SCRIPT" feature/theirs --quiet 2>&1)" || true
if [ -z "$out" ]; then ok "--quiet prints nothing"
else bad "--quiet prints nothing" "got: $out"; fi

# --- default branch is not hardcoded --------------------------------------
# A repo whose default branch is 'master' must work identically. Hardcoding
# 'main' would make every branch here look like it had no commits.
git init --quiet --bare "$SANDBOX/origin2.git"
git init --quiet "$SANDBOX/work2"
cd "$SANDBOX/work2" || exit 1
git config user.email "me@example.com"
git config user.name "Me"
git config commit.gpgsign false
git config core.autocrlf false
git remote add origin "$SANDBOX/origin2.git"
echo base > f.txt; git add f.txt; git commit --quiet -m base
git branch -M master
git push --quiet -u origin master
git remote set-head origin -a >/dev/null 2>&1
git switch --quiet -c feature/theirs2
echo x >> f.txt
git -c user.email="other@example.com" -c user.name="Other Dev" commit --quiet -am "their work"
git push --quiet -u origin feature/theirs2
git switch --quiet master
expect "master-default repo still detects CLAIMED" 1 feature/theirs2

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
