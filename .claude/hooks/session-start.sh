#!/bin/bash
# SessionStart hook: injects current working context on startup, resume, clear, and compact.
# No vector DB, no dependencies — just git state + quick references.

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

echo "=== SESSION CONTEXT ==="
echo ""

# 1. Current git branch + recent commits
if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
  BRANCH=$(git -C "$ROOT" branch --show-current 2>/dev/null)
  echo "## Git State"
  echo "Branch: $BRANCH"
  echo ""
  echo "Recent commits:"
  git -C "$ROOT" log --oneline -5 2>/dev/null
  echo ""

  # Uncommitted changes summary, capped
  CHANGES=$(git -C "$ROOT" status --short 2>/dev/null)
  if [ -n "$CHANGES" ]; then
    echo "Uncommitted changes:"
    echo "$CHANGES" | head -15
    CHANGE_COUNT=$(echo "$CHANGES" | wc -l | tr -d ' ')
    if [ "$CHANGE_COUNT" -gt 15 ]; then
      echo "... and $((CHANGE_COUNT - 15)) more files"
    fi
    echo ""
  fi
fi

# 2. Self-heal the git pre-push hook wiring (silent no-op when already set)
if [ -f "$ROOT/bin/install-git-hooks.sh" ]; then
  bash "$ROOT/bin/install-git-hooks.sh" "$ROOT"
fi

# 3. Quick references
echo "## Quick References"
echo "- Known issues: docs/common-gotchas.md"
echo "- Decision history: docs/decision-log.md"
echo "- Bug workflow: docs/methodology/bug-protocol.md (/bug-report)"
echo ""
echo "=== END SESSION CONTEXT ==="
