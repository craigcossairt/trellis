#!/bin/bash
# PreToolUse hook (Edit|Write): blocks edits to secrets, lock files, and generated files.
# Exit code 2 = block the tool call and surface the message to the model.
#
# The payload arrives on STDIN as JSON (not in $TOOL_INPUT - see hook-file-path.sh for
# the history of that bug). This hook fails CLOSED: if a payload arrives but no file
# path can be parsed from it, the edit is blocked rather than waved through. It exists
# to stop secret writes; silently allowing on a parse failure was exactly the old bug.
#
# Customize: add project-specific generated-file patterns to GENERATED below
# (e.g. '\.g\.dart$|\.freezed\.dart$' for Flutter, '_pb2\.py$' for protobuf).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0

file_path=$(printf '%s' "$PAYLOAD" | bash "$HOOK_DIR/hook-file-path.sh")

if [ -z "$file_path" ]; then
  echo 'BLOCKED: could not parse the target file path from the hook payload, so the sensitive-file check could not run. Confirm with the user before editing.' >&2
  exit 2
fi

# Templates for secrets files are fine to edit (.env.example, config.sample, ...)
if echo "$file_path" | grep -qiE '\.(example|sample|template)$'; then
  exit 0
fi

SECRETS='\.env($|\.)|secrets|credentials|\.pem$|\.key$|github_pat|id_rsa|id_ed25519'
LOCKS='package-lock\.json$|pubspec\.lock$|yarn\.lock$|bun\.lock|Cargo\.lock$|poetry\.lock$|composer\.lock$'
GENERATED='\.generated\.|\.min\.(js|css)$'

if echo "$file_path" | grep -qiE "$SECRETS|$LOCKS|$GENERATED"; then
  echo 'BLOCKED: This is a sensitive, lock, or generated file. Confirm with the user before editing.' >&2
  exit 2
fi
exit 0
