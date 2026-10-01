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

# 1a. OPT-IN: is the shared main checkout still parked?
# Only for a project whose main checkout is marked shared:
#   git config --local project.sharedCheckout true
# Unmarked (every fresh copy), this section runs one config read and prints
# nothing. Marked, it runs bin/check-main-checkouts.sh on the MAIN checkout -
# found through the common git dir, so a session started in a linked worktree
# still judges the checkout every session shares, not its own worktree. A guard
# on the tool-call command line never sees git run from a script file; this
# checks the end state instead, whoever caused it. Silence means parked or not
# opted in, nothing else: a checker that is missing or cannot run says so.
# Runs synchronously and costs one `git status` of the main checkout, which
# counts against this hook's timeout on a very large tree.
if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
  mc_rc=0
  mc_raw=$(git -C "$ROOT" config --local --get project.sharedCheckout 2>/dev/null) || mc_rc=$?
  if [ "$mc_rc" -eq 0 ]; then
    mc_shared=""
    mc_shared=$(git -C "$ROOT" config --local --type=bool --get project.sharedCheckout 2>/dev/null) || mc_shared=invalid
    if [ "$mc_shared" = invalid ]; then
      echo "## Main checkout check FAILED"
      echo "project.sharedCheckout is set to '$mc_raw', which is not a boolean. Nothing was checked."
      echo ""
    elif [ "$mc_shared" = true ]; then
      mc_common=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || mc_common=""
      case "$mc_common" in
        */.git) mc_main=${mc_common%/.git} ;;
        *) mc_main="" ;;
      esac
      if [ ! -f "$ROOT/bin/check-main-checkouts.sh" ]; then
        echo "## Main checkout check MISSING"
        echo "project.sharedCheckout is on, but bin/check-main-checkouts.sh was not found."
        echo "Whether the shared main checkout is parked is UNVERIFIED."
        echo ""
      elif [ -z "$mc_main" ]; then
        echo "## Main checkout check FAILED"
        echo "Could not locate the main checkout (git common dir: '${mc_common:-unreadable}')."
        echo "This is a broken check, NOT a parked result."
        echo ""
      else
        mc_out=$(bash "$ROOT/bin/check-main-checkouts.sh" "$mc_main" 2>&1)
        mc_rc=$?
        if [ "$mc_rc" -eq 1 ]; then
          echo "## Main checkout not parked"
          echo "The shared main checkout is off its default branch, dirty, or carries a repo-local git identity."
          echo "Every session shares it. Do not work in it; find out who left it this way before repairing."
          echo "$mc_out"
          echo ""
        elif [ "$mc_rc" -ne 0 ]; then
          echo "## Main checkout check FAILED"
          echo "Could not check the shared main checkout (exit $mc_rc)."
          echo "This is a broken check, NOT a parked result."
          echo "$mc_out"
          echo ""
        fi
      fi
    fi
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
