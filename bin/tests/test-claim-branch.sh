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

SCRIPT="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)/claim-branch.sh"
[ -f "$SCRIPT" ] || { echo "cannot find claim-branch.sh next to this test" >&2; exit 1; }

# The fixture must not inherit the host's git configuration. A global
# core.hooksPath runs the host's hooks during fixture commits, and a global
# user.email would keep the "unset user.email" case passing for the wrong
# reason. Neutralise both for the whole suite rather than per-case.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# Fixture commands must fail CLOSED. Without this the suite runs on against a
# half-built sandbox and reports whatever that broken state happens to produce -
# which is green often enough to be dangerous. `set -e` would do it too, but it
# also aborts on the deliberate non-zero exits this suite is built around, so
# guard the setup explicitly instead of arming errexit over the assertions.
must() {
  "$@" || { echo "FIXTURE FAILED: $*" >&2; exit 1; }
}

# expect <label> <expected-exit> <args...>
expect() {
  local label="$1" want="$2"; shift 2
  local out rc=0
  out="$(bash "$SCRIPT" "$@" 2>&1)" || rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$label"; else bad "$label" "wanted exit $want, got $rc: $out"; fi
}

SANDBOX="$(mktemp -d 2>/dev/null || mktemp -d -t claimbranch)"
trap 'rm -rf "$SANDBOX"' EXIT

must git init --quiet --bare "$SANDBOX/origin.git"
# Point the bare repo's HEAD at the branch this fixture actually pushes. With
# the host's config neutralised there is no init.defaultBranch, so git picks its
# built-in default and `git remote set-head -a` below cannot resolve a HEAD that
# names a branch nobody ever creates. That failure used to be swallowed by a
# 2>&1 redirect, leaving the script to fall through to its candidate loop - so
# the "default branch is not hardcoded" case was passing without ever exercising
# the symbolic-ref path it exists to cover.
must git -C "$SANDBOX/origin.git" symbolic-ref HEAD refs/heads/main
must git init --quiet "$SANDBOX/work"
cd "$SANDBOX/work" || exit 1
must git config user.email "me@example.com"
must git config user.name  "Me"
must git config commit.gpgsign false
must git config core.autocrlf false
must git remote add origin "$SANDBOX/origin.git"

echo base > f.txt
must git add f.txt
must git commit --quiet -m base
must git branch -M main
must git push --quiet -u origin main
must git remote set-head origin -a >/dev/null

# A branch carrying someone else's commit.
must git switch --quiet -c feature/theirs
echo x >> f.txt
must git -c user.email="other@example.com" -c user.name="Other Dev" commit --quiet -am "their work"
must git push --quiet -u origin feature/theirs

# A branch carrying only mine.
must git switch --quiet main
must git switch --quiet -c feature/mine
echo y >> f.txt
must git commit --quiet -am "my work"
must git push --quiet -u origin feature/mine

# A branch with mine on top of theirs - the shallow-fetch trap. An older commit
# by someone else must still be found under newer commits of yours.
must git switch --quiet feature/theirs
must git switch --quiet -c feature/mixed
echo z >> f.txt
must git commit --quiet -am "my later work"
must git push --quiet -u origin feature/mixed

must git switch --quiet main

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
must git config user.email "me@example.com"

# An origin that cannot be reached at all. Until this case existed, every other
# test could pass with the script's `ls-remote` error branch rewritten to
# `exit 0` - the suite had no way to tell "no such branch" from "could not ask",
# which is the single collapse the header above says half these cases defend.
BROKEN="$SANDBOX/broken"
must git clone --quiet "$SANDBOX/origin.git" "$BROKEN"
must git -C "$BROKEN" config user.email "me@example.com"
must git -C "$BROKEN" remote set-url origin "$SANDBOX/no-such-repo.git"
rc=0; out="$(cd "$BROKEN" && bash "$SCRIPT" feature/theirs 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then ok "unreachable origin is 2, not 0"
else bad "unreachable origin is 2, not 0" "got $rc: $out"; fi

# The same answer under --quiet. A hook calls the quiet form, so a collapse that
# only happened on that path would be invisible to every case above.
rc=0; out="$(cd "$BROKEN" && bash "$SCRIPT" feature/theirs --quiet 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then ok "unreachable origin under --quiet is 2, not 0"
else bad "unreachable origin under --quiet is 2, not 0" "got $rc: $out"; fi

# The two cases above no longer reach the AUTHOR path's ls-remote guard, and
# that is worth stating rather than discovering later. Since the lease check runs
# first, an origin that is down fails inside lease_read and the script exits 2
# there - so rewriting the author path's error branch to `exit 0` leaves this
# whole suite green. Measured: that mutation produced 0 red across 16 cases,
# against a predicted 2. The cases still assert the right verdict; they stopped
# asserting it about the code they were written for.
#
# So drive the branch reader directly: a `git` shim that passes the LEASE reads
# through (they answer "no such ref") and fails the ls-remote that names the
# branch itself. That is the only way into the guard now, and it is also a real
# state - a remote can go away between two calls.
#
# Matched by REF NAME, not by call count. This shim used to fail "the second
# ls-remote", which stopped being the branch read the day the lease read grew a
# second ls-remote (the probe of the old refs/claims/ namespace). A count is a
# fact about the implementation; the ref name is the thing under test.
REAL_GIT="$(command -v git)"
SHIM="$SANDBOX/shim"
must mkdir -p "$SHIM"
cat > "$SHIM/git" <<EOS
#!/usr/bin/env bash
is_lsr=0
for a in "\$@"; do [ "\$a" = "ls-remote" ] && is_lsr=1; done
if [ "\$is_lsr" = 1 ]; then
  n=0
  [ -f "$SANDBOX/.lsr-count" ] && n="\$(cat "$SANDBOX/.lsr-count")"
  printf '%s' "\$((n + 1))" > "$SANDBOX/.lsr-count"
  for a in "\$@"; do
    # 128 is git's transport failure, and it is neither 0 (found) nor 2
    # (--exit-code, no match) - so it must land in the error branch.
    case "\$a" in
      feature/mine|refs/heads/feature/mine) : > "$SANDBOX/.lsr-branch-fired"; exit 128 ;;
    esac
  done
fi
exec "$REAL_GIT" "\$@"
EOS
must chmod +x "$SHIM/git"
rm -f "$SANDBOX/.lsr-count" "$SANDBOX/.lsr-branch-fired"
rc=0; out="$(PATH="$SHIM:$PATH" bash "$SCRIPT" feature/mine 2>&1)" || rc=$?
if [ "$rc" -eq 2 ]; then ok "an origin that fails on the BRANCH read (not the lease read) is 2, not 0"
else bad "an origin that fails on the BRANCH read (not the lease read) is 2, not 0" "got $rc: $out"; fi
# Fixture sanity: the shim must have failed the branch read, and only after the
# lease read passed through, or the case above proved nothing at all.
if [ -e "$SANDBOX/.lsr-branch-fired" ] && [ "$(cat "$SANDBOX/.lsr-count" 2>/dev/null)" -ge 2 ]; then
  ok "fixture sanity: the shim failed the BRANCH ls-remote, after the lease read"
else
  bad "fixture sanity: the shim failed the BRANCH ls-remote, after the lease read" \
      "fired: $([ -e "$SANDBOX/.lsr-branch-fired" ] && echo yes || echo no), calls: $(cat "$SANDBOX/.lsr-count" 2>/dev/null || echo 0)"
fi
rm -f "$SANDBOX/.lsr-count" "$SANDBOX/.lsr-branch-fired"

# --- reporting ------------------------------------------------------------
out="$(bash "$SCRIPT" feature/theirs 2>&1)" || true
case "$out" in
  *other@example.com*) ok "CLAIMED output names the other author" ;;
  *) bad "CLAIMED output names the other author" "got: $out" ;;
esac

# Assert the EXIT CODE here as well as the silence. Checking output alone lets
# a --quiet that short-circuits the whole check and returns 0 pass this case:
# silent and wrong looks identical to silent and right.
rc=0; out="$(bash "$SCRIPT" feature/theirs --quiet 2>&1)" || rc=$?
if [ -z "$out" ]; then ok "--quiet prints nothing"
else bad "--quiet prints nothing" "got: $out"; fi
if [ "$rc" -eq 1 ]; then ok "--quiet still exits 1 on a CLAIMED branch"
else bad "--quiet still exits 1 on a CLAIMED branch" "got $rc"; fi

# --- default branch is not hardcoded --------------------------------------
# A repo whose default branch is 'master' must work identically. Hardcoding
# 'main' would make every branch here look like it had no commits.
must git init --quiet --bare "$SANDBOX/origin2.git"
must git -C "$SANDBOX/origin2.git" symbolic-ref HEAD refs/heads/master
must git init --quiet "$SANDBOX/work2"
cd "$SANDBOX/work2" || exit 1
must git config user.email "me@example.com"
must git config user.name "Me"
must git config commit.gpgsign false
must git config core.autocrlf false
must git remote add origin "$SANDBOX/origin2.git"
echo base > f.txt; must git add f.txt; must git commit --quiet -m base
must git branch -M master
must git push --quiet -u origin master
must git remote set-head origin -a >/dev/null
must git switch --quiet -c feature/theirs2
echo x >> f.txt
must git -c user.email="other@example.com" -c user.name="Other Dev" commit --quiet -am "their work"
must git push --quiet -u origin feature/theirs2
must git switch --quiet master
expect "master-default repo still detects CLAIMED" 1 feature/theirs2

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
