#!/bin/bash
# Shared helper: extract the target file path from a hook payload arriving on STDIN.
# Echoes the path on stdout, or nothing.
#
# Why stdin, and why this much care: Claude Code delivers the hook payload as JSON
# on stdin - the $TOOL_INPUT environment variable is NOT populated. An early version
# of these hooks read $TOOL_INPUT, always got an empty string, and silently no-op'd
# on every call: the formatter never ran and, worse, the sensitive-file blocker never
# blocked. A hook that no-ops is indistinguishable from a hook that passes, so nothing
# complained. Verify hooks with a deliberate violation (see SETUP.md § Sanity check),
# never by absence of complaints.
#
# Parsing: jq when available; otherwise POSIX sed. Never grep -P - BSD grep (macOS)
# has no -P, and GNU grep -P dies on non-UTF-8 locales (seen in Git Bash on Windows).
# Both key spellings are checked: Claude Code sends snake_case (file_path), other
# harnesses routed through the adapter may send camelCase (filePath).
set -uo pipefail

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  printf '%s' "$PAYLOAD" | jq -r '
    .tool_input.file_path // .tool_input.filePath //
    .toolInput.file_path  // .toolInput.filePath  //
    .tool_response.filePath // .tool_input.path // empty' 2>/dev/null
else
  OUT=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$OUT" ] || OUT=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"filePath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  printf '%s' "$OUT"
fi
