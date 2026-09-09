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
# contrivance. The unstaged-edits NOTE further down does not cover it either:
# staging is exactly what makes the working tree clean again, so that NOTE goes
# quiet in the one case that matters here.
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
