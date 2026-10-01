#!/usr/bin/env bash
# =============================================================================
# test-reference-transaction.sh - behavioral tests for .githooks/reference-transaction
# =============================================================================
# The hook refuses a HEAD move off the default branch in a checkout marked as a
# SHARED main checkout, from inside git. That catches git run from a script
# file, which a guard reading the agent's tool-call command line never sees.
#
# It is opt-in and must be inert everywhere else, so what it must NOT refuse is
# pinned as hard as what it must:
#
#   - any checkout that has not set `project.sharedCheckout=true` in its own
#     local config - which is every fresh copy of this template;
#   - `git worktree add` from the shared checkout. It runs with the same git
#     dir, cwd and environment as a real switch; only which HEAD.lock git holds
#     tells them apart;
#   - commits, fetches, fast-forwards, reset --soft and a diverged
#     `pull --rebase`, which fire the same hook on every run.
#
# Two halves: end to end (real git operations in fixture repos whose
# core.hooksPath runs a copy of the hook) and direct (the hook invoked by hand
# with a chosen state, stdin and lock file, to pin each signal on its own).
#
# Hermetic: global and system git config are isolated; nothing outside $TMP is
# read or written.
#
# Run:  bash bin/tests/test-reference-transaction.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/../.." >/dev/null && pwd)"
HOOK="$ROOT/.githooks/reference-transaction"
INSTALLER="$ROOT/bin/install-git-hooks.sh"
for f in "$HOOK" "$INSTALLER" "$ROOT/.githooks/pre-push"; do
  [ -f "$f" ] || { echo "cannot find $f" >&2; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/gitconfig-global"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
unset PROJECT_ALLOW_CHECKOUT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# The hook stands aside on git older than 2.48 (see its header), so on such a
# git every refusal case below would fail for a reason that has nothing to do
# with the hook. That is "could not run", not a red result - say so and exit 2.
gv=$(git version); gv=${gv#git version }
gmaj=${gv%%.*}; grest=${gv#*.}; gmin=${grest%%.*}
case "$gmaj$gmin" in *[!0-9]*|'') echo "cannot parse '$(git version)' - suite did not run" >&2; exit 2 ;; esac
if [ "$gmaj" -lt 2 ] || { [ "$gmaj" -eq 2 ] && [ "$gmin" -lt 48 ]; }; then
  echo "git $gv predates 2.48, where the hook stands aside by design - suite did not run" >&2
  exit 2
fi
echo "git $gv"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /' | head -8; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

# make_repo <case> [branch] [off] - sets REPO: a main checkout on <branch>
# (default main) with one commit and the hook wired through core.hooksPath.
# Marked shared (project.sharedCheckout=true) unless the third arg is "off".
REPO=""
make_repo() {
  local branch="${2:-main}"
  REPO="$TMP/$1/app"
  mkdir -p "$REPO/.githooks"
  must git init -q -b "$branch" "$REPO"
  must git -C "$REPO" config core.autocrlf false
  cp "$HOOK" "$REPO/.githooks/reference-transaction"
  chmod +x "$REPO/.githooks/reference-transaction"
  must git -C "$REPO" add -A
  must git -C "$REPO" commit -q -m fixture
  must git -C "$REPO" config core.hooksPath .githooks
  [ "${3:-}" = off ] || must git -C "$REPO" config --local project.sharedCheckout true
  [ "$branch" = main ] || must git -C "$REPO" config --local project.defaultBranch "$branch"
}

# hookless <git args...> - a fixture step that has to move HEAD in a marked
# checkout. It runs git with hooks pointed at an empty directory, rather than
# using the bypass or lifting the marker, so no fixture depends on any behavior
# a case is there to test: a mutation that breaks the bypass or the marker read
# should turn those cases red, not abort the suite at an unrelated fixture.
mkdir -p "$TMP/nohooks"
hookless() { must git -c core.hooksPath="$TMP/nohooks" "$@"; }

head_of() { git -C "$1" symbolic-ref -q --short HEAD || echo DETACHED; }

OUT=""; RC=0
run() { OUT=$("$@" 2>&1); RC=$?; }

# refused <label> <repo> <expected-branch> <expected-substring...> - the last
# run failed, HEAD is still on the expected branch, and stderr carries each
# substring. Asserting the TEXT matters: a hook that refuses because it broke
# exits non-zero too.
refused() {
  local label="$1" repo="$2" want="$3"; shift 3
  local n
  [ "$RC" -ne 0 ] || { bad "$label: git exited 0" "$OUT"; return; }
  [ "$(head_of "$repo")" = "$want" ] || { bad "$label: HEAD moved to $(head_of "$repo")" "$OUT"; return; }
  for n in "$@"; do
    printf '%s' "$OUT" | grep -Fq -- "$n" || { bad "$label: message lacks '$n'" "$OUT"; return; }
  done
  ok "$label"
}
# allowed <label> - the last run exited 0.
allowed() { if [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1: exit $RC" "$OUT"; fi; }

echo "inert unless enabled"

make_repo unmarked main off
run git -C "$REPO" switch -c feat
allowed "unmarked checkout: switch -c goes through (every fresh copy)"
if [ "$(head_of "$REPO")" = feat ]; then ok "unmarked checkout: HEAD really moved"; else bad "unmarked checkout: HEAD really moved: it did not"; fi

make_repo falsemark main off
must git -C "$REPO" config --local project.sharedCheckout false
run git -C "$REPO" switch -c feat
allowed "project.sharedCheckout=false: switch goes through"

make_repo globalmark main off
git config --file "$GIT_CONFIG_GLOBAL" project.sharedCheckout true
run git -C "$REPO" switch -c feat
allowed "marked only in GLOBAL config: not this checkout's opt-in"
: > "$GIT_CONFIG_GLOBAL"

# The installer wires core.hooksPath=.githooks, so every adopter who runs it
# gets this hook too. It must change nothing for them.
INST="$TMP/installer/app"
must mkdir -p "$INST/bin" "$INST/.githooks"
cp "$INSTALLER" "$INST/bin/install-git-hooks.sh"
cp "$ROOT/.githooks/pre-push" "$INST/.githooks/pre-push"
cp "$HOOK" "$INST/.githooks/reference-transaction"
chmod +x "$INST/.githooks/pre-push" "$INST/.githooks/reference-transaction"
must git init -q -b main "$INST"
must git -C "$INST" config core.autocrlf false
must git -C "$INST" add -A
must git -C "$INST" commit -q -m fixture
must bash "$INST/bin/install-git-hooks.sh" "$INST"
if [ "$(git -C "$INST" config --get core.hooksPath)" = .githooks ]; then ok "installer wires .githooks (so this hook is live)"; else bad "installer wires .githooks (so this hook is live): it did not"; fi
run git -C "$INST" switch -c feat
allowed "installed but not enabled: switch goes through"
run git -C "$INST" switch main
allowed "installed but not enabled: switch back goes through"

echo "end to end (enabled)"

make_repo switch
run git -C "$REPO" switch -c feat
refused "switch -c in the shared checkout" "$REPO" main "BLOCKED" "switch to 'feat'" "worktree add" "PROJECT_ALLOW_CHECKOUT=1" "project.sharedCheckout"

make_repo script
cat > "$TMP/script/move.sh" <<EOF
#!/bin/sh
cd "$REPO" && git checkout -b agent/task-42
EOF
run sh "$TMP/script/move.sh"
refused "checkout -b from a script file" "$REPO" main "switch to 'agent/task-42'"

make_repo detach
run git -C "$REPO" checkout --detach
refused "checkout --detach" "$REPO" main "detach HEAD at"

make_repo existing
must git -C "$REPO" branch other
run git -C "$REPO" switch other
refused "switch to an existing branch" "$REPO" main "switch to 'other'"

make_repo wtadd
run git -C "$REPO" worktree add -q ../app-wt-x -b feat
allowed "worktree add -b from the shared checkout"
if [ "$(head_of "$REPO")" = main ]; then ok "worktree add left the shared checkout on main"; else bad "worktree add left the shared checkout on main: it moved"; fi
if [ "$(head_of "$REPO/../app-wt-x")" = feat ]; then ok "worktree add landed on feat"; else bad "worktree add landed on feat: it did not"; fi

make_repo wtexisting
must git -C "$REPO" branch other
run git -C "$REPO" worktree add -q ../app-wt-y other
allowed "worktree add of an existing branch"

make_repo wtdetach
run git -C "$REPO" worktree add -q --detach ../app-wt-z
allowed "worktree add --detach"

# The local config is shared with every linked worktree, so the marker is
# visible there too. Only the git-dir == common-dir check keeps it out.
make_repo inworktree
hookless -C "$REPO" worktree add -q ../app-wt-w -b feat
run git -C "$REPO/../app-wt-w" switch -c feat2
allowed "switch inside a linked worktree of a shared checkout"

make_repo commit
run git -C "$REPO" commit -q --allow-empty -m c2
allowed "commit on main"

make_repo resetsoft
must git -C "$REPO" commit -q --allow-empty -m c2
run git -C "$REPO" reset -q --soft HEAD~1
allowed "reset --soft on main (writes ORIG_HEAD)"

make_repo pull
must git clone -q "$REPO" "$TMP/pull/upstream-work"
must git -C "$TMP/pull/upstream-work" commit -q --allow-empty -m upstream
must git -C "$TMP/pull/upstream-work" push -q origin HEAD:refs/heads/incoming
run git -C "$REPO" merge -q --ff-only incoming
allowed "fast-forward merge on main"
run git -C "$REPO" fetch -q "$TMP/pull/upstream-work" main
allowed "fetch into the shared checkout (writes FETCH_HEAD)"

make_repo rebasepull
must git clone -q "$REPO" "$TMP/rebasepull/other"
must git -C "$TMP/rebasepull/other" commit -q --allow-empty -m theirs
must git -C "$REPO" commit -q --allow-empty -m ours
run git -C "$REPO" -c rebase.autoStash=false pull -q --rebase "$TMP/rebasepull/other" main
allowed "pull --rebase on a diverged main (the rebase detaches HEAD)"
if [ ! -d "$REPO/.git/rebase-merge" ] && [ "$(head_of "$REPO")" = main ]; then ok "pull --rebase finished on main"; else bad "pull --rebase finished on main: left mid-rebase or off main"; fi

make_repo backtomain
hookless -C "$REPO" switch -q -c stray
run git -C "$REPO" switch main
allowed "returning to main from another branch"
if [ "$(head_of "$REPO")" = main ]; then ok "switch main landed on main"; else bad "switch main landed on main: it did not"; fi

make_repo bypass
run env PROJECT_ALLOW_CHECKOUT=1 git -C "$REPO" switch -c feat
allowed "PROJECT_ALLOW_CHECKOUT=1 bypass"

make_repo trunk trunk
run git -C "$REPO" switch -c feat
refused "project.defaultBranch=trunk: switch off trunk refused" "$REPO" trunk "switch to 'feat'" "'trunk'"
must git -C "$REPO" branch main
run git -C "$REPO" switch main
refused "project.defaultBranch=trunk: 'main' is not special" "$REPO" trunk "switch to 'main'"
hookless -C "$REPO" switch -q main
run git -C "$REPO" switch trunk
allowed "project.defaultBranch=trunk: returning to trunk"

echo "direct"

# direct <label> <want-exit> <state> <stdin> - run the hook in $REPO.
direct() {
  local label="$1" want="$2" st="$3" in="$4" got
  got=$( cd "$REPO" && printf '%s\n' "$in" | sh "$HOOK" "$st" 2>/dev/null; echo $? )
  if [ "$got" = "$want" ]; then ok "$label"; else bad "$label: exit $got, want $want"; fi
}
Z=0000000000000000000000000000000000000000
SWITCH="$Z ref:refs/heads/feat HEAD"

make_repo direct
touch "$REPO/.git/HEAD.lock"
direct "prepared, own HEAD.lock held: refuse" 1 prepared "$SWITCH"
direct "committed: never refuse" 0 committed "$SWITCH"
direct "aborted: never refuse" 0 aborted "$SWITCH"
direct "ORIG_HEAD is not HEAD" 0 prepared "$Z $Z ORIG_HEAD"
direct "FETCH_HEAD is not HEAD" 0 prepared "$Z $Z FETCH_HEAD"
direct "HEAD back to main" 0 prepared "$Z ref:refs/heads/main HEAD"
direct "branch ref line before the HEAD line" 1 prepared "$Z $Z refs/heads/feat
$SWITCH"
mkdir "$REPO/.git/reftable"
direct "reftable repo: stand aside" 0 prepared "$SWITCH"
rmdir "$REPO/.git/reftable"
mkdir "$REPO/.git/rebase-merge"
direct "rebase in progress: let its detach through" 0 prepared "$Z 1111111111111111111111111111111111111111 HEAD"
rmdir "$REPO/.git/rebase-merge"
must git -C "$REPO" config --local --unset project.sharedCheckout
direct "lock held but not marked shared: allow" 0 prepared "$SWITCH"
must git -C "$REPO" config --local project.sharedCheckout notabool
direct "unparseable marker value: allow (fail open)" 0 prepared "$SWITCH"
must git -C "$REPO" config --local project.sharedCheckout true

# The version gate. Before 2.48 git also passes the log-only HEAD update of
# every commit with HEAD.lock held, so the hook must stand aside there. A shim
# `git` reports a chosen version and hands every other call to the real git.
REAL_GIT=$(command -v git)
SHIM="$TMP/shim"; mkdir -p "$SHIM"
shim_version() {
  cat > "$SHIM/git" <<EOF
#!/bin/sh
[ "\$1" = version ] && { echo "git version $1"; exit 0; }
exec "$REAL_GIT" "\$@"
EOF
  chmod +x "$SHIM/git"
}
direct_shim() { # <label> <want> <version>
  local got
  shim_version "$3"
  got=$( cd "$REPO" && printf '%s\n' "$SWITCH" | PATH="$SHIM:$PATH" sh "$HOOK" prepared 2>/dev/null; echo $? )
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1: exit $got, want $2"; fi
}
direct_shim "git 2.47 (log-only HEAD lines): stand aside" 0 "2.47.1"
direct_shim "vendor git 2.39: stand aside" 0 "2.39.5 (Apple Git-154)"
direct_shim "git 2.48: refuse" 1 "2.48.0"
direct_shim "git 3.0: refuse" 1 "3.0.0"
direct_shim "unparseable version: stand aside" 0 "unknown"
rm "$REPO/.git/HEAD.lock"
direct "own HEAD.lock free (worktree add): allow" 0 prepared "$SWITCH"

mkdir -p "$TMP/notarepo"
got=$( cd "$TMP/notarepo" && printf '%s\n' "$SWITCH" | GIT_CEILING_DIRECTORIES="$TMP" sh "$HOOK" prepared 2>/dev/null; echo $? )
# Outside a repository the marker read is the first git call to fail, so this
# pins THAT read failing open. The later rev-parse reads cannot be made to fail
# while the marker read succeeds in the same directory, so their fail-open arms
# have no isolating case.
if [ "$got" = 0 ]; then ok "not a repository: allow (fail open)"; else bad "not a repository: allow (fail open), got exit $got"; fi

echo
echo "reference-transaction hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
