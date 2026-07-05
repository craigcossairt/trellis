#!/bin/bash
# PreToolUse hook (Edit|Write): blocks edits to secrets, lock files, and generated files.
# Exit code 2 = block the tool call and surface the message to the model.
#
# Customize: add project-specific generated-file patterns to GENERATED below
# (e.g. '\.g\.dart$|\.freezed\.dart$' for Flutter, '_pb2\.py$' for protobuf).

# POSIX sed, not grep -P: BSD grep (macOS) has no -P, and GNU grep -P breaks on non-UTF-8 locales.
file_path=$(printf '%s' "${TOOL_INPUT:-}" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$file_path" ] && exit 0

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
