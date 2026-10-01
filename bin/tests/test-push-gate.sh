#!/usr/bin/env bash
# =============================================================================
# test-push-gate.sh - hermetic tests for .githooks/pre-push and bin/verify-green.sh
# =============================================================================
# The push gate is two layers with two separate bypasses, and the property most
# worth pinning is that they stay separate: PROJECT_SKIP_VERIFY is the routine
# docs-only escape, so if it also lifted the branch-claim layer, collision
# detection would quietly switch itself off every time someone pushed a README
# fix.
#
# The other property is the one every guard in this repo is about: a layer that
# CANNOT run must block, never wave the push through. Exit 2 from the claim
# check is "I could not tell", and could-not-tell is not free.
#
# Hermetic: bare repo in a temp dir plays origin, the real scripts are copied in
# and GREEN_COMMANDS is filled with a trivial command. No network.
#
# Run:  bash bin/tests/test-push-gate.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOOK_SRC="$ROOT/.githooks/pre-push"
VERIFY_SRC="$ROOT/bin/verify-green.sh"
CLAIM_SRC="$ROOT/bin/claim-branch.sh"
for f in "$HOOK_SRC" "$VERIFY_SRC" "$CLAIM_SRC"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset PROJECT_SESSION_ID

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
must() { "$@" || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t pushgate)"
trap 'rm -rf "$TMP"' EXIT

ORIGIN="$TMP/origin.git"
must git init -q --bare "$ORIGIN"
must git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

WORK="$TMP/work"
must git init -q "$WORK"
must git -C "$WORK" config user.email 'me@example.com'
must git -C "$WORK" config user.name  'Me'
must git -C "$WORK" config commit.gpgsign false
must git -C "$WORK" config core.autocrlf false
must git -C "$WORK" remote add origin "$ORIGIN"

# The repo under test carries its own copies of the scripts, because the hook
# resolves them from the pushed repo's root.
must mkdir -p "$WORK/bin" "$WORK/.githooks"
must cp "$HOOK_SRC" "$WORK/.githooks/pre-push"
must cp "$CLAIM_SRC" "$WORK/bin/claim-branch.sh"
must chmod +x "$WORK/.githooks/pre-push"

# GREEN_COMMANDS is a FILL-IN slot in the shipped script. Fill it with something
# trivially true so the gate is CONFIGURED here. Patched by line, so a rename of
# the array is caught as a fixture failure rather than silently leaving the gate
# off - which would make every green-layer case below pass for the wrong reason.
fill_green() { # $1 command to run
  local out="$WORK/bin/verify-green.sh"
  must awk -v cmd="$1" '
    /^GREEN_COMMANDS=\(/ { print; print "  \"" cmd "\""; injected = 1; next }
    { print }
    END { exit !injected }
  ' "$VERIFY_SRC" > "$out" || { echo "FIXTURE FAILED: GREEN_COMMANDS not found in $VERIFY_SRC" >&2; exit 1; }
  must git -C "$WORK" add bin/verify-green.sh
}
fill_green 'true'
if bash "$WORK/bin/verify-green.sh" --check-configured; then
  ok "fixture sanity: the filled-in gate reports itself configured"
else
  bad "fixture sanity: the filled-in gate reports itself configured" "--check-configured said no"
fi

echo base > "$WORK/f.txt"
must git -C "$WORK" add .
must git -C "$WORK" commit -qm base
must git -C "$WORK" branch -M main
# Seed main WITHOUT the hook, so the fixture's own setup cannot be blocked by
# the thing under test.
must git -C "$WORK" push -q -u origin main
must git -C "$WORK" remote set-head origin -a >/dev/null
must git -C "$WORK" config core.hooksPath .githooks

echo "push gate"

# --- verify-green -----------------------------------------------------------

# --absolute-git-dir, not --git-dir: the latter answers a bare ".git" relative to
# the repo, which resolves against this suite's cwd instead of the fixture's.
marker_dir() { printf '%s/green' "$(git -C "$WORK" rev-parse --absolute-git-dir)"; }
index_tree() { git -C "$WORK" write-tree; }

rm -rf "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "a passing check records a marker (exit 0)"
else bad "a passing check records a marker (exit 0)" "exit $RC: $OUT"; fi
if [ -f "$(marker_dir)/$(index_tree)" ]; then ok "the marker is named for the INDEX tree"
else bad "the marker is named for the INDEX tree" "no marker at $(marker_dir)/$(index_tree)"; fi

fill_green 'false'
rm -rf "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "a failing check refuses (non-zero)"
else bad "a failing check refuses (non-zero)" "exit 0: $OUT"; fi
if [ ! -d "$(marker_dir)" ] || [ -z "$(ls -A "$(marker_dir)" 2>/dev/null)" ]; then
  ok "a failing check writes no marker"
else bad "a failing check writes no marker" "markers exist: $(ls -A "$(marker_dir)")"; fi

# THE mid-run guard. The check itself stages a file, which is exactly what an
# agent session does while a slow suite runs: the index moves, so the tree the
# marker would name is not the tree anything ran against.
fill_green 'echo later > staged-midrun.txt && git add staged-midrun.txt'
rm -rf "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "an index that MOVES mid-run refuses the marker"
else bad "an index that MOVES mid-run refuses the marker" "exit 0: $OUT"; fi
case "$OUT" in
  *"index MOVED"*) ok "the refusal says the index moved, not that a check failed" ;;
  *)               bad "the refusal says the index moved, not that a check failed" "got: $OUT" ;;
esac
if [ ! -f "$(marker_dir)/$(index_tree)" ]; then ok "no marker is written for the moved tree"
else bad "no marker is written for the moved tree" "marker exists for $(index_tree)"; fi

# COMMITTING mid-run must still be allowed: `git commit` builds from the index
# without changing it, so the tree is unmoved. A gate that fired here would be
# switched off within a day, which is the failure mode that matters more than
# the one above.
must git -C "$WORK" commit -qm 'staged during the previous run'
fill_green 'git commit --allow-empty -qm midrun-commit'
rm -rf "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "COMMITTING mid-run is still allowed (the index does not move)"
else bad "COMMITTING mid-run is still allowed (the index does not move)" "exit $RC: $OUT"; fi

fill_green 'true'
must git -C "$WORK" commit -qm 'restore passing checks'

# A passing unstaged repair must not certify the failing version in the index.
fill_green 'grep -qx repaired f.txt && git restore f.txt'
printf 'broken\n' > "$WORK/f.txt"
must git -C "$WORK" add f.txt
printf 'repaired\n' > "$WORK/f.txt"
rm -rf "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
  ok "an unstaged passing repair cannot certify the failing index"
else bad "an unstaged passing repair cannot certify the failing index" "exit $RC: $OUT"; fi
must git -C "$WORK" restore --source=HEAD --staged --worktree f.txt
for index_flag in assume-unchanged skip-worktree; do
  fill_green 'grep -qx repaired f.txt'
  printf 'broken\n' > "$WORK/f.txt"
  must git -C "$WORK" add f.txt
  must git -C "$WORK" update-index "--$index_flag" f.txt
  FLAG_BEFORE="$(git -C "$WORK" ls-files -v f.txt)"
  printf 'repaired\n' > "$WORK/f.txt"
  rm -rf "$(marker_dir)"
  OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
  if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
    ok "$index_flag cannot hide a passing repair from verification"
  else bad "$index_flag cannot hide a passing repair from verification" "exit $RC: $OUT"; fi
  if [ "$(git -C "$WORK" ls-files -v f.txt)" = "$FLAG_BEFORE" ]; then
    ok "verification preserves the user's $index_flag flag"
  else bad "verification preserves the user's $index_flag flag" "index flag changed"; fi
  must git -C "$WORK" update-index "--no-$index_flag" f.txt
  must git -C "$WORK" restore --source=HEAD --staged --worktree f.txt

  fill_green "git update-index --$index_flag f.txt && echo repaired > f.txt"
  rm -rf "$(marker_dir)"
  OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
  if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
    ok "$index_flag introduced during checks prevents a marker"
  else bad "$index_flag introduced during checks prevents a marker" "exit $RC: $OUT"; fi
  must git -C "$WORK" update-index "--no-$index_flag" f.txt
  must git -C "$WORK" restore f.txt
done
fill_green 'test -f local-input.txt'
printf 'only on this machine\n' > "$WORK/local-input.txt"
rm -rf "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
  ok "an untracked input cannot satisfy checks for a commit without it"
else bad "an untracked input cannot satisfy checks for a commit without it" "exit $RC: $OUT"; fi
must git -C "$WORK" add local-input.txt
fill_green 'true'

# A filesystem failure must not become a successful verification receipt.
rm -rf "$(marker_dir)"
printf 'occupied\n' > "$(marker_dir)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && [[ "$OUT" != *"GREEN - marker recorded"* ]]; then
  ok "a failed marker directory creation reports failure, never GREEN"
else bad "a failed marker directory creation reports failure, never GREEN" "exit $RC: $OUT"; fi
rm -f "$(marker_dir)"

must mkdir -p "$(marker_dir)/$(index_tree)"
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && [[ "$OUT" != *"GREEN - marker recorded"* ]]; then
  ok "a failed marker file write reports failure, never GREEN"
else bad "a failed marker file write reports failure, never GREEN" "exit $RC: $OUT"; fi
rm -rf "$(marker_dir)"

fill_green 'echo changed > f.txt'
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
  ok "tracked changes made during checks prevent a marker"
else bad "tracked changes made during checks prevent a marker" "exit $RC: $OUT"; fi
must git -C "$WORK" restore f.txt

fill_green 'echo new > during-check.txt'
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
  ok "untracked inputs created during checks prevent a marker"
else bad "untracked inputs created during checks prevent a marker" "exit $RC: $OUT"; fi
must git -C "$WORK" add during-check.txt

printf 'build/\n' > "$WORK/.gitignore"
must git -C "$WORK" add .gitignore
must mkdir -p "$WORK/build"
printf 'existing dependency\n' > "$WORK/build/dependency"
fill_green 'test -f build/dependency && echo compiled > build/output'
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ] && [ -f "$(marker_dir)/$(index_tree)" ]; then
  ok "ignored dependencies and generated output do not block verification"
else bad "ignored dependencies and generated output do not block verification" "exit $RC: $OUT"; fi

# Simulate Git operational failures at the command boundary. The normal Git
# executable handles all fixture operations and every other subcommand.
REAL_GIT="$(command -v git)"
must mkdir -p "$TMP/git-failure"
cat > "$TMP/git-failure/git" <<'SH'
#!/usr/bin/env bash
case "$FAIL_GIT_COMMAND:$1:${2:-}" in
  diff:diff:*|index-flags:ls-files:-v|untracked-inputs:ls-files:--others) exit 2 ;;
esac
exec "$REAL_GIT" "$@"
SH
must chmod +x "$TMP/git-failure/git"
fill_green 'true'
for failed_command in diff index-flags untracked-inputs; do
  rm -rf "$(marker_dir)"
  OUT="$( cd "$WORK" && PATH="$TMP/git-failure:$PATH" REAL_GIT="$REAL_GIT" FAIL_GIT_COMMAND="$failed_command" bash bin/verify-green.sh 2>&1 )"; RC=$?
  if [ "$RC" -ne 0 ] && [ ! -f "$(marker_dir)/$(index_tree)" ]; then
    ok "git $failed_command operational errors refuse verification"
  else bad "git $failed_command operational errors refuse verification" "exit $RC: $OUT"; fi
done
must git -C "$WORK" commit -qm 'verification fixtures'

# --- the hook: green layer --------------------------------------------------

new_branch() { # $1 name -> a branch with one commit, no marker
  local file="${1//\//-}.txt"   # branch names carry slashes; file names must not
  must git -C "$WORK" checkout -q -b "$1" main
  printf '%s\n' "$1" > "$WORK/$file"
  must git -C "$WORK" add "$file"
  must git -C "$WORK" commit -qm "work on $1"
}

rm -rf "$(marker_dir)"
new_branch feat/nomarker
OUT="$( git -C "$WORK" push -q origin feat/nomarker 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "an unverified push is BLOCKED"
else bad "an unverified push is BLOCKED" "it went through: $OUT"; fi
case "$OUT" in
  *"no green verification"*) ok "the block names the green gate" ;;
  *)                         bad "the block names the green gate" "got: $OUT" ;;
esac

OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
[ "$RC" -eq 0 ] || { echo "FIXTURE FAILED: verify-green did not pass" >&2; exit 1; }
OUT="$( git -C "$WORK" push -q origin feat/nomarker 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "a verified push goes through"
else bad "a verified push goes through" "exit $RC: $OUT"; fi

new_branch feat/bypass
OUT="$( PROJECT_SKIP_VERIFY=1 git -C "$WORK" push -q origin feat/bypass 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "PROJECT_SKIP_VERIFY=1 lifts the green layer"
else bad "PROJECT_SKIP_VERIFY=1 lifts the green layer" "exit $RC: $OUT"; fi

# --- the hook: branch-claim layer -------------------------------------------
# A branch carrying another author's commit. The claim layer must refuse it even
# though the green marker is present, and refuse it under PROJECT_SKIP_VERIFY.

must git -C "$WORK" checkout -q -b feat/claimed main
printf 'theirs\n' > "$WORK/theirs.txt"
must git -C "$WORK" add theirs.txt
must git -C "$WORK" -c user.email='other@example.com' -c user.name='Other' commit -qm 'their work'
must git -C "$WORK" -c core.hooksPath=/dev/null push -q -u origin feat/claimed
printf 'mine\n' >> "$WORK/theirs.txt"
must git -C "$WORK" add theirs.txt
must git -C "$WORK" commit -qm 'my work on their branch'
OUT="$( cd "$WORK" && bash bin/verify-green.sh 2>&1 )"; RC=$?
[ "$RC" -eq 0 ] || { echo "FIXTURE FAILED: verify-green did not pass on feat/claimed" >&2; exit 1; }

OUT="$( git -C "$WORK" push -q origin feat/claimed 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "a push to a branch another author owns is BLOCKED"
else bad "a push to a branch another author owns is BLOCKED" "it went through: $OUT"; fi
case "$OUT" in
  *other@example.com*) ok "the claim block names the other author" ;;
  *)                   bad "the claim block names the other author" "got: $OUT" ;;
esac

# THE separation case. PROJECT_SKIP_VERIFY is reached for routinely; folding the
# two bypasses together would silently disable collision detection with it.
OUT="$( PROJECT_SKIP_VERIFY=1 git -C "$WORK" push -q origin feat/claimed 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "PROJECT_SKIP_VERIFY does NOT lift the branch-claim layer"
else bad "PROJECT_SKIP_VERIFY does NOT lift the branch-claim layer" "it went through: $OUT"; fi

OUT="$( PROJECT_ALLOW_SHARED_BRANCH=1 git -C "$WORK" push -q origin feat/claimed 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "PROJECT_ALLOW_SHARED_BRANCH=1 lifts the branch-claim layer"
else bad "PROJECT_ALLOW_SHARED_BRANCH=1 lifts the branch-claim layer" "exit $RC: $OUT"; fi

# And the claim bypass must not lift the GREEN layer either - the separation
# has to hold in both directions, or one of the two is decorative.
new_branch feat/claimbypass
OUT="$( PROJECT_ALLOW_SHARED_BRANCH=1 git -C "$WORK" push -q origin feat/claimbypass 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "PROJECT_ALLOW_SHARED_BRANCH does NOT lift the green layer"
else bad "PROJECT_ALLOW_SHARED_BRANCH does NOT lift the green layer" "it went through: $OUT"; fi

# --- could-not-tell must block ----------------------------------------------
# The hook's three branches on the claim check's exit code, driven by a STUB
# rather than by a broken remote.
#
# The first draft pointed origin at a path with no repository, on the theory
# that claim-branch.sh would answer 2. It does - but git never got that far:
# the push failed to open the remote and the hook never ran at all. The case
# asserted a non-zero exit and got one, from the transport. Passing for the
# wrong reason, and only the message assertion caught it.
#
# A stub also puts the right thing under test. claim-branch.sh's own exit codes
# are pinned by its two suites; what is unproven here is whether the HOOK reads
# them, and in particular whether it treats 2 as free.
stub_repo() { # $1 dir  $2 claim-exit-code (empty = no claim script at all)
  local dir="$1" code="${2:-}"
  must git init -q "$dir"
  must git -C "$dir" config user.email 'me@example.com'
  must git -C "$dir" config user.name 'Me'
  must git -C "$dir" config commit.gpgsign false
  must git -C "$dir" config core.autocrlf false
  must git -C "$dir" remote add origin "$ORIGIN"
  must mkdir -p "$dir/.githooks"
  must cp "$HOOK_SRC" "$dir/.githooks/pre-push"
  must chmod +x "$dir/.githooks/pre-push"
  # No bin/verify-green.sh anywhere in these fixtures, so the green layer is
  # provably OFF and anything that happens is the claim layer's doing.
  if [ -n "$code" ]; then
    must mkdir -p "$dir/bin"
    printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$dir/bin/claim-branch.sh"
  fi
  must git -C "$dir" config core.hooksPath .githooks
  printf 'seed\n' > "$dir/seed.txt"
  must git -C "$dir" add seed.txt
  must git -C "$dir" commit -qm seed
}

stub_repo "$TMP/stub2" 2
must git -C "$TMP/stub2" checkout -q -b feat/unknown
OUT="$( git -C "$TMP/stub2" push -q origin feat/unknown 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "a claim check that could NOT RUN blocks the push (2 is not free)"
else bad "a claim check that could NOT RUN blocks the push (2 is not free)" "it went through: $OUT"; fi
case "$OUT" in
  *"could not run"*) ok "the block says the check could not run, not that the branch is claimed" ;;
  *)                 bad "the block says the check could not run, not that the branch is claimed" "got: $OUT" ;;
esac

stub_repo "$TMP/stub0" 0
must git -C "$TMP/stub0" checkout -q -b feat/free
OUT="$( git -C "$TMP/stub0" push -q origin feat/free 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "a claim check that answers FREE lets the push through"
else bad "a claim check that answers FREE lets the push through" "exit $RC: $OUT"; fi

# A DELETION is claim-checked even though the green layer skips it: deleting a
# branch another session is working on is the same collision as pushing over it.
stub_repo "$TMP/stubdel" 1
OUT="$( git -C "$TMP/stubdel" push -q origin ":feat/free" 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "a branch DELETION is claim-checked too"
else bad "a branch DELETION is claim-checked too" "the deletion went through: $OUT"; fi

# --- both layers off pushes freely ------------------------------------------
# A project that filled in neither slot must not be gated at all, or a fresh
# template clone cannot push. Passing an empty code leaves out the claim script
# entirely, which is the SETUP.md prune.
stub_repo "$TMP/ungated" ''
must git -C "$TMP/ungated" checkout -q -b feat/ungated
OUT="$( git -C "$TMP/ungated" push -q origin feat/ungated 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "with neither layer configured the push is free"
else bad "with neither layer configured the push is free" "exit $RC: $OUT"; fi

# --- the green layer's own enablement probe --------------------------------
# ABSENT, OFF and BROKEN are three different facts about verify-green.sh, and
# the hook used to collapse the last two: `! bash "$VERIFY" --check-configured`
# mapped ANY non-zero onto "not configured - pushing unchecked", so a script
# with a syntax error or a missing interpreter silently disabled the gate on a
# repo that had configured it. The case above covers ABSENT; these cover the
# other two. No claim script in either fixture, so whatever happens is the
# green layer's doing.
stub_repo "$TMP/greenoff" ''
must mkdir -p "$TMP/greenoff/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/greenoff/bin/verify-green.sh"
must git -C "$TMP/greenoff" checkout -q -b feat/greenoff
OUT="$( git -C "$TMP/greenoff" push -q origin feat/greenoff 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exit 1 from --check-configured means OFF, and the push is free"
else bad "exit 1 from --check-configured means OFF, and the push is free" "exit $RC: $OUT"; fi

stub_repo "$TMP/greenbroken" ''
must mkdir -p "$TMP/greenbroken/bin"
printf '#!/usr/bin/env bash\nexit 2\n' > "$TMP/greenbroken/bin/verify-green.sh"
must git -C "$TMP/greenbroken" checkout -q -b feat/greenbroken
OUT="$( git -C "$TMP/greenbroken" push -q origin feat/greenbroken 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ]; then ok "a verify-green.sh that CRASHES blocks, rather than reading as OFF"
else bad "a verify-green.sh that CRASHES blocks, rather than reading as OFF" "it went through: $OUT"; fi
# Assert the MESSAGE too: both outcomes are non-zero-ish to a skim reader, and
# the failure that shipped was the wrong DIAGNOSIS, not the wrong exit code.
case "$OUT" in
  *"cannot be determined"*) ok "the block says the gate's state is unknown, not that it is off" ;;
  *)                        bad "the block says the gate's state is unknown, not that it is off" "got: $OUT" ;;
esac
case "$OUT" in
  *"not configured"*) bad "a broken gate is NOT reported as an unconfigured one" "got: $OUT" ;;
  *)                  ok "a broken gate is NOT reported as an unconfigured one" ;;
esac

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
