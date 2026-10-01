#!/usr/bin/env bash
# =============================================================================
# test-session-start-main-checkout.sh - the opt-in main-checkout section of
# .claude/hooks/session-start.sh
# =============================================================================
# bin/tests/test-check-main-checkouts.sh pins the checker. This pins the
# wiring, which is where a working check goes quietly dead - and, because the
# section is OPT-IN, where it could leak into projects that never asked for it.
#
#   1. Not opted in: the checker is never run and nothing is printed, whatever
#      state the checkout is in. That is every fresh copy of the template.
#   2. Opted in (`project.sharedCheckout=true` in the repo's local config):
#      a parked checkout prints nothing; an unparked one gets a heading naming
#      what is wrong.
#   3. A session started in a LINKED worktree still judges the main checkout,
#      which is the one every session shares - not the worktree it started in.
#   4. A checker that is missing or fails says MISSING or FAILED, never
#      nothing. Silence must only ever mean "parked" or "not opted in".
#
# Hermetic: temp git repos, global git config neutralised, the real hook run
# against them with CLAUDE_PROJECT_DIR pointing at the fixture.
#
# Run:  bash bin/tests/test-session-start-main-checkout.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/../.." >/dev/null && pwd)"
HOOK="$ROOT/.claude/hooks/session-start.sh"
CHECKER="$ROOT/bin/check-main-checkouts.sh"
for f in "$HOOK" "$CHECKER"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/gitconfig-global"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_NOSYSTEM=1
GIT_ID=(-c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false)

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; printf '%s\n' "$OUT" | grep -A4 'Main checkout' | sed 's/^/        /' | head -10; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

# make_fixture <name> [checker|stub|none] [branch] - sets REPO: a main checkout
# directory named mainco-<name>, on <branch> (default main), clean, with the
# checker committed so its presence does not itself make the tree dirty.
#   checker - the real bin/check-main-checkouts.sh (default)
#   stub    - a checker that records it ran and exits 2 (a broken checker)
#   none    - no checker at all
REPO=""
make_fixture() {
  local kind="${2:-checker}"
  REPO="$TMP/$1/mainco-$1"
  mkdir -p "$REPO/bin"
  if [ "${4:-}" = sep ]; then
    must git init -q -b "${3:-main}" --separate-git-dir "$TMP/$1/gitdir" "$REPO"
  else
    must git init -q -b "${3:-main}" "$REPO"
  fi
  must git -C "$REPO" config core.autocrlf false
  case "$kind" in
    checker) cp "$CHECKER" "$REPO/bin/check-main-checkouts.sh" ;;
    stub)    printf '#!/usr/bin/env bash\n: > "%s/ran"\necho "stub could not read"\nexit 2\n' "$TMP/$1" > "$REPO/bin/check-main-checkouts.sh" ;;
    none)    : > "$REPO/bin/.keep" ;;
  esac
  must git -C "$REPO" add -A
  must git -C "$REPO" "${GIT_ID[@]}" commit -q -m fixture
}
mark() { must git -C "$REPO" config --local project.sharedCheckout "${1:-true}"; }

OUT=""; RC=0
run() { OUT="$(CLAUDE_PROJECT_DIR="$1" bash "$HOOK" </dev/null 2>&1)"; RC=$?; }

has()    { printf '%s' "$OUT" | grep -qF -- "$1"; }
# check <label> <want-heading 0|1> <heading> [needle...]
check() {
  local label="$1" want="$2" heading="$3"; shift 3
  local good=1 n
  [ "$RC" -eq 0 ] || good=0
  has '=== END SESSION CONTEXT ===' || good=0
  if [ "$want" = 1 ]; then has "$heading" || good=0; else has "$heading" && good=0; fi
  for n in "$@"; do has "$n" || good=0; done
  if [ "$good" = 1 ]; then ok "$label"; else bad "$label (exit $RC)"; fi
}

echo "== not opted in: inert =="
make_fixture plain stub
must git -C "$REPO" switch -q -c agent/task-42
printf 'x' > "$REPO/dirt.txt"
must git -C "$REPO" config user.email someone@example.invalid
run "$REPO"
check "unmarked, off main, dirty, local identity: no heading" 0 "Main checkout"
if [ ! -e "$TMP/plain/ran" ]; then ok "unmarked: the checker was never run"; else bad "unmarked: the checker was never run: it ran"; fi

make_fixture marked-false stub
mark false
must git -C "$REPO" switch -q -c feat
run "$REPO"
check "project.sharedCheckout=false: no heading" 0 "Main checkout"
if [ ! -e "$TMP/marked-false/ran" ]; then ok "marked false: the checker was never run"; else bad "marked false: the checker was never run: it ran"; fi

echo "== opted in =="
make_fixture parked; mark
run "$REPO"
check "marked, parked: no heading" 0 "Main checkout"

make_fixture offmain; mark
must git -C "$REPO" switch -q -c agent/task-42
run "$REPO"
check "marked, off main: reported, naming the branch" 1 "## Main checkout not parked" "agent/task-42" "mainco-offmain"

make_fixture trunk checker trunk; mark
must git -C "$REPO" config --local project.defaultBranch trunk
run "$REPO"
check "marked, on project.defaultBranch=trunk: parked" 0 "Main checkout"

make_fixture nochecker none; mark
run "$REPO"
check "marked, checker missing: MISSING" 1 "## Main checkout check MISSING"

make_fixture broken stub; mark
run "$REPO"
check "marked, checker exits 2: FAILED, not parked" 1 "## Main checkout check FAILED" "NOT a parked result" "stub could not read"

make_fixture badvalue stub; mark notabool
run "$REPO"
check "marker that is not a boolean: FAILED, naming the key" 1 "## Main checkout check FAILED" "project.sharedCheckout"

# A session started from a linked worktree: ROOT is the worktree, and the
# hook must still judge the MAIN checkout. The marker lives in the shared
# config, so the worktree sees it.
make_fixture linked; mark
must git -C "$REPO" worktree add -q "$TMP/linked/wt" -b side
must git -C "$REPO" switch -q -c stray
run "$TMP/linked/wt"
check "from a linked worktree: judges the main checkout" 1 "## Main checkout not parked" "stray" "mainco-linked"

make_fixture linkedparked; mark
must git -C "$REPO" worktree add -q "$TMP/linkedparked/wt" -b side
run "$TMP/linkedparked/wt"
check "from a linked worktree, main parked: no heading" 0 "Main checkout"

# `git init --separate-git-dir` keeps the git dir elsewhere, so the common dir
# is not <checkout>/.git. The main checkout must still be found and judged.
make_fixture sepdir checker main sep; mark
must git -C "$REPO" switch -q -c agent/task-9
run "$REPO"
check "separate git dir: judges the main checkout" 1 "## Main checkout not parked" "agent/task-9" "mainco-sepdir"

make_fixture sepparked checker main sep; mark
run "$REPO"
check "separate git dir, parked: no heading" 0 "Main checkout"

echo
echo "session-start main-checkout: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
