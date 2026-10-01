#!/usr/bin/env bash
# =============================================================================
# test-check-main-checkouts.sh - behavioral tests for bin/check-main-checkouts.sh
# =============================================================================
# Why the checker exists: a guard that reads the agent's tool-call command line
# never sees git run from a script file. An agent that writes its git steps
# into a `.sh` file and runs it can leave a shared main checkout on another
# branch, full of dirty files, with a repo-local git identity - and the guard
# saw nothing. The checker reports that END STATE however it was reached.
#
# Its dangerous failures are not crashes: (a) reporting clean over a checkout
# it could not read, which renders identically to "parked", and (b) missing
# one of the three kinds of damage (branch, dirt, identity).
#
# Three states are pinned, never two: 0 parked, 1 found a problem, 2 could not
# check. Every unreadable input must land on 2 and never on 0, and a problem in
# one checkout must not hide an unreadable one (or the reverse).
#
# Hermetic: every case builds its own repos under a temp dir, with global and
# system git config switched off, so the machine's own config cannot leak in.
#
# Run:  bash bin/tests/test-check-main-checkouts.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$HERE/../check-main-checkouts.sh"
[ -f "$SCRIPT" ] || { echo "cannot find check-main-checkouts.sh at $SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# No machine config: an empty global file, no system file.
: > "$TMP/gitconfig-global"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_NOSYSTEM=1
GIT_ID=(-c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false)

pass=0; fail=0

# make_repo <dir> [branch] - a main checkout on <branch> (default main) with one
# tracked file, one ignored pattern, and a clean tree.
make_repo() {
  local d="$1"
  git init -q -b "${2:-main}" "$d"
  git -C "$d" config core.autocrlf false
  printf 'a\nb\n' > "$d/tracked.txt"
  printf 'build/\n' > "$d/.gitignore"
  git -C "$d" add tracked.txt .gitignore
  git -C "$d" "${GIT_ID[@]}" commit -q -m init
}

OUT=""; RC=0
run() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; RC=$?; }

# expect <label> <want-exit> [<fixed string the output must contain>]...
# Compares the exact code, never a truthiness bucket: collapsing 1 and 2 is the
# defect this suite exists to catch. Each needle is asserted separately, so a
# message that names the wrong thing fails even when the code is right.
expect() {
  local label="$1" want="$2"; shift 2
  local good=1 needle
  [ "$RC" -eq "$want" ] || good=0
  for needle in "$@"; do
    printf '%s' "$OUT" | grep -Fq -- "$needle" || good=0
  done
  if [ "$good" = 1 ]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$label"
  else
    fail=$((fail+1))
    echo "  FAIL $label - expected exit $want, got $RC; wanted: $*"
    echo "       output: $(printf '%s' "$OUT" | head -5 | tr '\n' '|')"
  fi
}

# expect_silent <label> - exit 0 and nothing printed.
expect_silent() {
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else
    fail=$((fail+1))
    echo "  FAIL $1 - expected exit 0 and no output, got $RC"
    echo "       output: $(printf '%s' "$OUT" | head -5 | tr '\n' '|')"
  fi
}

# fresh [branch] - build the next fixture repo and set R to its path. Not a
# $(...) subshell: the counter has to survive, or every case would reuse one
# path.
n=0; R=""
fresh() { n=$((n+1)); R="$TMP/r$n"; make_repo "$R" "${1:-main}"; }

# ------------------------------------------------------------------ parked ---
fresh; run "$R"
expect_silent "parked: on main, clean, no local identity"

fresh; mkdir -p "$R/build"; printf 'x' > "$R/build/out.bin"; run "$R"
expect_silent "ignored: an ignored file is not dirt"

fresh; git config --file "$GIT_CONFIG_GLOBAL" user.email global@example.invalid; run "$R"
expect_silent "global-identity: user.email in GLOBAL config is fine"
: > "$GIT_CONFIG_GLOBAL"

# Opt-in markers live in local config too. They are not an identity.
fresh; git -C "$R" config --local project.sharedCheckout true; run "$R"
expect_silent "marker: project.sharedCheckout in local config is not a finding"

# ---------------------------------------------------------- default branch ---
fresh trunk; git -C "$R" config --local project.defaultBranch trunk; run "$R"
expect_silent "default-branch: on the configured default (trunk) is parked"

fresh trunk; git -C "$R" config --local project.defaultBranch trunk
git -C "$R" switch -q -c main; run "$R"
expect "default-branch: main is not special when the default is trunk" 1 "on branch 'main'" "not trunk"

# ------------------------------------------------------------------ branch ---
fresh; git -C "$R" switch -q -c agent/task-42; run "$R"
expect "off-main: names the branch it is on" 1 "agent/task-42" "not main"

fresh; git -C "$R" switch -q -c main-backup; run "$R"
expect "near-miss name: main-backup is not main" 1 "main-backup"

fresh; git -C "$R" checkout -q --detach; run "$R"
expect "detached: says detached" 1 "detached"

# ------------------------------------------------------------------- dirty ---
fresh; printf 'changed\n' >> "$R/tracked.txt"; run "$R"
expect "modified: a tracked edit is reported" 1 "1 uncommitted or untracked" "tracked.txt"

fresh; printf 'git switch x\n' > "$R/move-branch.sh"; run "$R"
expect "untracked: a script file dropped in the root is reported" 1 "move-branch.sh"

fresh; printf 'a\r\nb\r\n' > "$R/tracked.txt"; run "$R"
expect "crlf-churn: a CR-only rewrite is reported" 1 "tracked.txt"

fresh; for i in 1 2 3 4 5 6 7; do printf 'x' > "$R/junk$i"; done; run "$R"
expect "count: reports the full count, lists only a few" 1 "7 uncommitted or untracked" "and 2 more"

# ---------------------------------------------------------------- identity ---
fresh; git -C "$R" config user.email someone@example.invalid; run "$R"
expect "local-email: a repo-local user.email is reported" 1 "user.email" "someone@example.invalid" "includeIf"

fresh; git -C "$R" config user.name "Some One"; run "$R"
expect "local-name: a repo-local user.name is reported" 1 "user.name"

# ------------------------------------------------------- every finding shown -
fresh; git -C "$R" switch -q -c agent/task-7; printf 'x' > "$R/s.sh"
git -C "$R" config user.email someone@example.invalid; run "$R"
expect "all-three: branch, dirt and identity in one report" 1 \
  "agent/task-7" "s.sh" "user.email"

# ----------------------------------------------------------- cannot check ----
run
expect "no-args: usage is could-not-check" 2 "usage"

run "$TMP/does-not-exist"
expect "missing: an absent path is could-not-check" 2 "cannot check" "does-not-exist"

mkdir -p "$TMP/plain"; run "$TMP/plain"
expect "not-a-repo: a plain directory is could-not-check" 2 "cannot check" "plain"

fresh; git -C "$R" worktree add -q "$TMP/linked" -b side; run "$TMP/linked"
expect "linked-worktree: refuses to judge a linked worktree" 2 "not a main checkout"

fresh; printf 'garbage' > "$R/.git/index"; run "$R"
expect "corrupt-index: a status that fails is could-not-check, not clean" 2 "cannot check"

fresh; printf '[user\n  email = broken\n' >> "$R/.git/config"; run "$R"
expect "bad-config: an unparseable config is could-not-check, not clean" 2 "cannot check"

# ------------------------------------------------ inherited git environment --
# `git -C` does not override GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE. Run from
# a git hook or `git rebase --exec`, the checker would read the PARKED repo
# those name and report it under the off-main checkout's name.
fresh; P="$R"; fresh; git -C "$R" switch -q -c agent/task-42
OUT="$(GIT_DIR="$P/.git" GIT_WORK_TREE="$P" GIT_INDEX_FILE="$P/.git/index" bash "$SCRIPT" "$R" 2>&1)"; RC=$?
expect "inherited-git-env: reads the named checkout, not an inherited GIT_DIR" 1 "agent/task-42"

# ------------------------------------------------------------ several paths --
fresh; A="$R"; fresh; B="$R"; git -C "$B" switch -q -c feat; run "$A" "$B"
expect "two-paths: one bad one parked is exit 1 and names the bad one" 1 "$B" "feat"

fresh; git -C "$R" switch -q -c feat; run "$R" "$TMP/does-not-exist"
expect "unknown-wins-exit: could-not-check outranks a finding, and both print" 2 \
  "feat" "does-not-exist"

fresh; A="$R"; fresh; run "$A" "$R"
expect_silent "two-parked: two clean checkouts are silent"

# ------------------------------------------------------- read-only on disk ---
# `git status` refreshes the index and would write it under a lock another
# session may hold. The checker must read without writing.
fresh; sleep 1; touch "$R/tracked.txt"; before=$(cksum < "$R/.git/index"); run "$R"
after=$(cksum < "$R/.git/index")
if [ "$before" = "$after" ] && [ "$RC" -eq 0 ]; then pass=$((pass+1)); printf '  ok   %s\n' "read-only: the index is not rewritten"; else
  fail=$((fail+1)); echo "  FAIL read-only: the index is not rewritten: it was (or exit $RC)"; fi

echo
echo "check-main-checkouts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
