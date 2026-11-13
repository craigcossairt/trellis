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
#    Context shape - neither tool reads a session hook's plain stdout. Cursor
#    takes {"additional_context": ...}; Grok reads only a top-level
#    {"systemMessage": ...} from a SessionStart reply. Printed raw, the block
#    reaches nobody and nothing says so.
# 3. Windows: a bare `bash` in the hook JSON is WSL's or nothing, so the tool
#    must be told to use Git Bash. docs/harness-support.md ("Windows") has the
#    exact lines for each tool.
#
# Where this fails OPEN, on purpose and worth knowing: a missing target allows
# (never brick a session because a path moved), and so does any exit from the
# sensitive-file hook other than 2 - the same rule Claude Code applies to a
# hook, so a hook that crashes (exit 1, 127, a kill) lets the edit through. The
# hook itself answers 2 for a payload it cannot read. A tool's `failClosed`
# covers only this script failing to start or to answer, not that case.
set -uo pipefail

HARNESS="${1:-}"
HOOK_ID="${2:-}"
if [ -z "$HARNESS" ] || [ -z "$HOOK_ID" ]; then
  echo "run-claude-hook.sh: usage: run-claude-hook.sh <grok|cursor> <hook-id>" >&2
  exit 0
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
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
  # Every control character becomes a space there, not only the line break: a
  # raw tab or carriage return inside a JSON string is a reply no parser reads.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  else
    printf '"%s"' "$(printf '%s' "$1" | tr '\000-\037' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
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
    # Neither tool adds this to the prompt today. Cursor's beforeSubmitPrompt
    # schema is {"continue": bool} and cannot inject context, so always let the
    # prompt through. Grok discards an allowing UserPromptSubmit hook's stdout
    # (its hooks guide, CLI 1.0.77), so .grok/hooks/hooks.json does not wire
    # this id and nothing is printed for it: a branch nothing runs and no test
    # covers is one nobody can tell from a working one.
    [ "$HARNESS" = "cursor" ] && printf '{"continue":true}'
    exit 0
    ;;
  session-start)
    # Cursor's sessionStart schema delivers context via additional_context.
    # Grok reads only a top-level systemMessage from a SessionStart reply.
    # Raw stdout is ignored by both.
    case "$HARNESS" in
      cursor) [ -n "$OUT" ] && printf '{"additional_context":%s}' "$(json_string "$OUT")" ;;
      grok)   [ -n "$OUT" ] && printf '{"systemMessage":%s}' "$(json_string "$OUT")" ;;
      *)      [ -n "$OUT" ] && printf '%s' "$OUT" ;;
    esac
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
