#!/bin/bash
# Points the repo's git hooks at the tracked .githooks/ directory.
#
# .git/hooks/ cannot be version controlled, so the tracked pre-push hook only
# runs once `core.hooksPath` is set - one command per clone that git itself
# cannot carry. Forgetting it on one machine leaves that clone with NO hook and
# no signal that anything is missing. So session-start.sh runs this every
# session and it self-heals.
#
# Idempotent and conservative:
#   unset                 -> set it, say so once
#   already .githooks     -> silent
#   set to something else -> warn, change NOTHING (never clobber a deliberate value)
#
# Usage: bash bin/install-git-hooks.sh [repo-path]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0
[ -f "$REPO/.githooks/pre-push" ] || exit 0

current=$(git -C "$REPO" config --get core.hooksPath 2>/dev/null || true)

# Setting core.hooksPath makes git ignore .git/hooks ENTIRELY, so anything
# already living there (husky, a hand-written local hook) would go quiet with no
# warning. Refuse rather than make that call silently.
hooks_dir="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/hooks"
legacy=''
if [ -d "$hooks_dir" ]; then
  for h in "$hooks_dir"/*; do
    [ -f "$h" ] || continue
    case "$h" in *.sample) continue ;; esac
    legacy="$legacy $(basename "$h")"
  done
fi
if [ -n "$legacy" ] && [ -z "$current" ]; then
  echo "## Not installing the git pre-push hook"
  echo "$hooks_dir already contains active hooks:$legacy"
  echo "Setting core.hooksPath would disable them silently. Move them into"
  echo ".githooks/ (version controlled there), then re-run:"
  echo "  bash bin/install-git-hooks.sh"
  exit 0
fi

if [ -z "$current" ]; then
  # Relative on purpose: git resolves a relative hooksPath against the working
  # tree in use, so one value covers the main checkout and every linked worktree.
  if git -C "$REPO" config core.hooksPath .githooks 2>/dev/null; then
    echo "## Git pre-push hook installed (core.hooksPath=.githooks)"
    echo "Pushes are gated once GREEN_COMMANDS in bin/verify-green.sh is configured."
  else
    echo "## Could not set core.hooksPath - pushes are UNGATED here."
    echo "Fix with: git -C \"$REPO\" config core.hooksPath .githooks"
  fi
elif [ "$current" != ".githooks" ]; then
  echo "## core.hooksPath=$current (not .githooks) - left as-is, but the tracked"
  echo "pre-push hook is NOT running. Back out with: git config --unset core.hooksPath"
fi
exit 0
