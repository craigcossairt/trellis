#!/bin/bash
# PostToolUse hook (Edit|Write): auto-format the edited file, dispatching by extension.
# Silently no-ops when the formatter isn't installed — safe to leave all branches in place.
#
# The payload arrives on STDIN as JSON (not in $TOOL_INPUT - see hook-file-path.sh).
#
# Customize: add or remove languages for your stack. Keep each branch's output short
# (tail) so hook noise stays out of the conversation.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

file_path=$(bash "$HOOK_DIR/hook-file-path.sh")
[ -z "$file_path" ] && exit 0
[ -f "$file_path" ] || exit 0

case "$file_path" in
  *.dart)
    command -v dart >/dev/null 2>&1 && dart format "$file_path" 2>&1 | tail -3 ;;
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md)
    command -v npx >/dev/null 2>&1 && npx --no-install prettier --write "$file_path" 2>/dev/null | tail -3 ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then ruff format "$file_path" 2>&1 | tail -3;
    elif command -v black >/dev/null 2>&1; then black -q "$file_path" 2>&1 | tail -3; fi ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$file_path" ;;
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt "$file_path" 2>&1 | tail -3 ;;
esac
exit 0
