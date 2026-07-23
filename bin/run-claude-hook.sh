#!/bin/bash
# Harness -> Claude hook adapter: lets Grok Build and Cursor run the SAME canonical
# hook scripts that .claude/settings.json wires for Claude Code, so every guardrail
# exists exactly once. One script serves both harnesses on purpose - two per-harness
# copies of this logic WILL drift apart silently.
#
# Usage: run-claude-hook.sh <grok|cursor> <hook-id>
#   hook-id: session-start | block-sensitive-files | format-on-edit | brain-enrich
#
# What it adapts:
# 1. Payload shape - Grok nests camelCase (toolInput.filePath), Cursor sends
#    top-level per-event keys (file_path / command / prompt). The canonical hooks
#    read stdin and accept every spelling via hook-file-path.sh, so the payload is
#    passed through untouched.
# 2. Verdict shape - Claude hooks block via exit 2 + a reason on stderr. Grok wants
#    {"decision":"deny"} on stdout; Cursor wants {"permission":"deny"} and needs an
#    explicit allow JSON even on a clean pass. Translated here.
# 3. Windows: invoke this script with Git Bash's FULL path in the hook JSON (see
#    .grok/hooks/hooks.json and .cursor/hooks.json) - a bare `bash` can resolve to
#    WSL, where HOME and every path are wrong.
#
# Missing targets fail OPEN (never brick a session because a path moved) - except
# the blocking hook's verdict itself, which the canonical script fails CLOSED.
set -uo pipefail

HARNESS="${1:-}"
HOOK_ID="${2:-}"
if [ -z "$HARNESS" ] || [ -z "$HOOK_ID" ]; then
  echo "run-claude-hook.sh: usage: run-claude-hook.sh <grok|cursor> <hook-id>" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CLAUDE_PROJECT_DIR="$ROOT"

case "$HOOK_ID" in
  session-start)         TARGET="$ROOT/.claude/hooks/session-start.sh" ;;
  block-sensitive-files) TARGET="$ROOT/.claude/hooks/block-sensitive-files.sh" ;;
  format-on-edit)        TARGET="$ROOT/.claude/hooks/format-on-edit.sh" ;;
  brain-enrich)          TARGET="$ROOT/brain/hooks/context-enrichment.sh" ;;
  *)
    echo "run-claude-hook.sh: unknown hook-id '$HOOK_ID'" >&2
    exit 0
    ;;
esac

allow_json() {
  case "$HARNESS" in
    cursor) printf '{"permission":"allow"}' ;;
    grok)   printf '{"decision":"allow"}' ;;
  esac
}

deny_json() {
  # $1 = reason. JSON-escape via jq when available; otherwise flatten to one
  # safe line. The full reason always also goes to stderr.
  local reason_json
  if command -v jq >/dev/null 2>&1; then
    reason_json=$(printf '%s' "$1" | jq -Rs .)
  else
    reason_json="\"$(printf '%s' "$1" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')\""
  fi
  case "$HARNESS" in
    cursor) printf '{"permission":"deny","userMessage":%s}' "$reason_json" ;;
    grok)   printf '{"decision":"deny","reason":%s}' "$reason_json" ;;
  esac
}

if [ ! -f "$TARGET" ]; then
  echo "run-claude-hook.sh: missing target $TARGET" >&2
  [ "$HOOK_ID" = "block-sensitive-files" ] && allow_json
  exit 0
fi

RAW="$(cat 2>/dev/null || true)"

TMP_OUT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/hook-out.$$")"
TMP_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/hook-err.$$")"
printf '%s' "$RAW" | bash "$TARGET" >"$TMP_OUT" 2>"$TMP_ERR"
RC=$?
OUT="$(cat "$TMP_OUT" 2>/dev/null || true)"
ERR="$(cat "$TMP_ERR" 2>/dev/null || true)"
rm -f "$TMP_OUT" "$TMP_ERR" 2>/dev/null || true

case "$HOOK_ID" in
  block-sensitive-files)
    if [ "$RC" -eq 2 ]; then
      REASON="$ERR"
      [ -n "$REASON" ] || REASON="Blocked by hook: $HOOK_ID"
      deny_json "$REASON"
      printf '%s\n' "$REASON" >&2
      exit 2
    fi
    allow_json
    [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
    exit 0
    ;;
  brain-enrich)
    # Emit the enrichment block once on stdout. (Cursor cannot inject prompt
    # context yet; harmless there, and ready the day it can.)
    [ -n "$OUT" ] && printf '%s\n' "$OUT"
    exit 0
    ;;
  *)
    # session-start / format-on-edit: passive passthrough.
    [ -n "$OUT" ] && printf '%s' "$OUT"
    [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
    exit 0
    ;;
esac
