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

# The checks ran against the WORKING tree; the marker attests the INDEX tree.
# Those differ when tracked files have unstaged edits - name them rather than
# silently vouching for content the checks never saw.
UNSTAGED=$(git diff --name-only 2>/dev/null)
if [ -n "$UNSTAGED" ]; then
  echo "verify-green: NOTE - these tracked files have unstaged edits NOT covered by the marker:" >&2
  while IFS= read -r f; do
    [ -n "$f" ] && printf '  %s\n' "$f" >&2
  done <<EOF
$UNSTAGED
EOF
  echo "verify-green: stage them and re-run if they belong in the verified commit." >&2
fi

MARKER_DIR="$(git rev-parse --git-dir)/green"
mkdir -p "$MARKER_DIR"
: > "$MARKER_DIR/$KEY"
echo "verify-green: GREEN - marker recorded for tree ${KEY:0:12}"
