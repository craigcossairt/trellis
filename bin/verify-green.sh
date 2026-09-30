#!/bin/bash
# Records a "green" marker for the current index state after the project's checks
# pass. The pre-push hook (.githooks/pre-push) then refuses to push any commit
# whose tree has no marker - so what lands on the remote is what the checks saw.
#
# Usage:
#   bash bin/verify-green.sh                    run the checks, record a marker on pass
#   bash bin/verify-green.sh --check-configured exit 0 if the gate is on (used by pre-push)
#
# Why a marker instead of running checks inside the push hook: a slow suite on
# every push (including every fix-and-repush cycle during review) makes the gate
# the first thing anyone disables. Pay the cost once per change-set, explicitly;
# the hook only checks the receipt. Any further edit produces a different tree
# and re-blocks, so a stale marker can never vouch for new code.
set -uo pipefail

# FILL IN: the commands that must pass before a push is allowed. The gate stays
# OFF until this array is non-empty, so a fresh template clone pushes freely.
# Each entry runs via `bash -c`, so compound commands work.
GREEN_COMMANDS=(
  # "npm run lint"
  # "npm test"
  # "flutter analyze --no-fatal-infos"
  # "flutter test"
)

if [ "${1:-}" = "--check-configured" ]; then
  [ "${#GREEN_COMMANDS[@]}" -gt 0 ] && exit 0
  exit 1
fi

if [ "${#GREEN_COMMANDS[@]}" -eq 0 ]; then
  echo "verify-green: no checks configured - fill in GREEN_COMMANDS in bin/verify-green.sh." >&2
  echo "verify-green: the push gate stays off until you do." >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "verify-green: not inside a git repository" >&2
  exit 1
fi

# The tree as it stands BEFORE any check runs, compared against the tree at the
# end. Without this, anything staged DURING the run moves the index and the
# marker is written for a tree nothing has run against.
#
# That is not theoretical. A real suite takes minutes and an agent session
# stages work continuously, so it is hit by ordinary use rather than by
# contrivance. The working-tree comparison alone does not cover it either:
# staging is exactly what makes the working tree clean again.
#
# Failing NOW rather than after the checks is deliberate. A write-tree that
# cannot run means no marker can be recorded whatever the checks say, so
# spending the whole run first only delays the same refusal.
KEY_BEFORE=$(git write-tree 2>/dev/null)
if [ -z "$KEY_BEFORE" ]; then
  echo "verify-green: 'git write-tree' failed, so no marker could be recorded." >&2
  echo "verify-green: git said:" >&2
  git write-tree 2>&1 >/dev/null | sed 's/^/  /' >&2
  echo "verify-green: resolve the index problem and re-run - refusing to spend the run." >&2
  exit 1
fi

# Checks read the working tree, but the receipt names the index. Refuse any
# tracked difference, including a failed comparison, before running checks.
working_tree_matches_index() {
  local rc=0 untracked index_entries entry
  # Git diff trusts these index flags rather than inspecting every tracked file.
  # Lowercase ls-files -v tags mean assume-unchanged; S means skip-worktree.
  # Refuse them without changing the user's index or sparse-checkout settings.
  if ! index_entries=$(git ls-files -v); then
    echo "verify-green: cannot inspect index flags - no marker recorded." >&2
    return 1
  fi
  while IFS= read -r entry; do
    case "$entry" in
      [abcdefghijklmnopqrstuvwxyzS]' '*)
        echo "verify-green: assume-unchanged or skip-worktree prevents verification: ${entry#??}" >&2
        echo "verify-green: use a full checkout with these flags cleared; sparse checkouts are unsupported." >&2
        return 1
        ;;
    esac
  done <<< "$index_entries"
  git diff --no-ext-diff --quiet --ignore-submodules=none -- || rc=$?
  case "$rc" in
    0) ;;
    1) echo "verify-green: unstaged tracked changes - stage or restore them and re-run." >&2 ;;
    *) echo "verify-green: cannot compare working tree with index (git exit $rc)." >&2 ;;
  esac
  [ "$rc" -eq 0 ] || return 1
  # Ignored dependencies/build outputs are allowed; ordinary untracked inputs
  # could make checks pass while being absent from the certified commit.
  if ! untracked=$(git ls-files --others --exclude-standard); then
    echo "verify-green: cannot enumerate untracked inputs - no marker recorded." >&2
    return 1
  fi
  if [ -n "$untracked" ]; then
    echo "verify-green: untracked inputs - stage, remove, or intentionally ignore them:" >&2
    printf '%s\n' "$untracked" >&2
    return 1
  fi
}
working_tree_matches_index || exit 1

i=0
total=${#GREEN_COMMANDS[@]}
for cmd in "${GREEN_COMMANDS[@]}"; do
  i=$((i + 1))
  echo "verify-green: [$i/$total] $cmd"
  if ! bash -c "$cmd"; then
    echo "verify-green: FAILED at '$cmd' - no marker written" >&2
    exit 1
  fi
done

# State key: the INDEX tree hash - exactly the tree `git commit` will record and
# a subsequent push will send. The hook resolves the pushed ref to its tree and
# looks for this hash, so verify -> commit -> push matches. On write-tree failure
# nothing is recorded: a shared "unknown" bucket would let one green authorize
# unrelated trees.
KEY=$(git write-tree 2>/dev/null)
if [ -z "$KEY" ]; then
  echo "verify-green: checks PASSED but 'git write-tree' failed - no marker recorded." >&2
  echo "verify-green: resolve the index problem and re-run." >&2
  exit 1
fi

# The tree MOVED while the checks were running, so the checks and the marker
# would describe different content. Refuse rather than record.
#
# Refusing LOUDLY rather than quietly filing under KEY_BEFORE: a marker for the
# old tree would not match the tree a push actually sends, so the push would be
# blocked anyway - with no explanation, which reads as "the gate is broken".
# A gate people believe is broken is a gate they bypass.
#
# STAGING is what trips this, not committing. `git commit` builds from the index
# without changing it, so committing already-staged content leaves this equal
# and is correctly allowed through. A gate that fired on that ordinary workflow
# would get switched off within a day.
if [ "$KEY" != "$KEY_BEFORE" ]; then
  echo "verify-green: the index MOVED during the run - refusing to record a marker." >&2
  echo "  the checks ran against tree ${KEY_BEFORE:0:12}" >&2
  echo "  the index now reads         ${KEY:0:12}" >&2
  echo "verify-green: something was staged while the checks were running, so a marker" >&2
  echo "written now would vouch for content that nothing verified. The checks" >&2
  echo "themselves PASSED - this is not a check failure. Re-run on a settled tree." >&2
  exit 1
fi

working_tree_matches_index || exit 1

if ! GIT_DIR_PATH=$(git rev-parse --git-dir) || [ -z "$GIT_DIR_PATH" ]; then
  echo "verify-green: cannot resolve marker location - no marker recorded." >&2
  exit 1
fi
MARKER_DIR="$GIT_DIR_PATH/green"
if ! mkdir -p "$MARKER_DIR" || ! { : > "$MARKER_DIR/$KEY"; } || [ ! -f "$MARKER_DIR/$KEY" ]; then
  echo "verify-green: cannot record marker - verification receipt failed." >&2
  exit 1
fi
echo "verify-green: GREEN - marker recorded for tree ${KEY:0:12}"
