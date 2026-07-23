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

json_string() {
  # JSON-escape $1 via jq when available; otherwise flatten to one safe line.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  else
    printf '"%s"' "$(printf '%s' "$1" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}

deny_json() {
  # $1 = reason (also always goes to stderr). Key names per each harness's
  # hook docs: Cursor wants snake_case user_message/agent_message.
  local reason_json
  reason_json=$(json_string "$1")
  case "$HARNESS" in
    cursor) printf '{"permission":"deny","user_message":%s,"agent_message":%s}' "$reason_json" "$reason_json" ;;
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
    # Grok injects UserPromptSubmit stdout directly - emit the block once.
    # Cursor's beforeSubmitPrompt schema is {"continue": bool} and cannot
    # inject context - always let the prompt through.
    if [ "$HARNESS" = "cursor" ]; then
      printf '{"continue":true}'
    else
      [ -n "$OUT" ] && printf '%s\n' "$OUT"
    fi
    exit 0
    ;;
  session-start)
    # Cursor's sessionStart schema delivers context via additional_context;
    # raw stdout would be ignored. Grok surfaces plain stdout.
    if [ "$HARNESS" = "cursor" ]; then
      [ -n "$OUT" ] && printf '{"additional_context":%s}' "$(json_string "$OUT")"
    else
      [ -n "$OUT" ] && printf '%s' "$OUT"
    fi
    [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
    exit 0
    ;;
  *)
    # format-on-edit: afterFileEdit has no output fields - passive passthrough.
    [ -n "$OUT" ] && printf '%s' "$OUT"
    [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
    exit 0
    ;;
esac
