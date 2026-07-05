#!/bin/bash
# Ingest the local project corpus into brain/raw/, then remind how to index it with QMD.
# Sources are configured in brain/config.sh. Idempotent: safe to re-run.
# Includes a secrets scan — the ingest FAILS if anything shaped like a real key lands in raw/.

set -euo pipefail

BRAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$BRAIN/.." && pwd)"
RAW="$BRAIN/raw"

# shellcheck source=../config.sh
source "$BRAIN/config.sh"

echo "Ingesting into $RAW"

for entry in "${INGEST_SOURCES[@]}"; do
  SRC="${entry%%:*}"
  DEST="${entry##*:}"
  mkdir -p "$RAW/$DEST"
  if [ -d "$ROOT/$SRC" ]; then
    cp -R "$ROOT/$SRC/." "$RAW/$DEST/"
    echo "  dir  $SRC -> raw/$DEST/"
  elif [ -f "$ROOT/$SRC" ]; then
    cp "$ROOT/$SRC" "$RAW/$DEST/"
    echo "  file $SRC -> raw/$DEST/"
  else
    echo "  skip $SRC (not found)"
  fi
done

if [ "${INGEST_GIT_LOG:-0}" = "1" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  mkdir -p "$RAW/git-commits"
  git -C "$ROOT" log --all \
    --pretty=format:'## %h %s%n**Author:** %an <%ae>%n**Date:** %ad%n%n%b%n%n---%n' \
    --date=iso > "$RAW/git-commits/$(basename "$ROOT").md"
  echo "  git  commit log -> raw/git-commits/"
fi

if [ -n "${INGEST_MEMORY_DIR:-}" ] && [ -d "$INGEST_MEMORY_DIR" ]; then
  mkdir -p "$RAW/memory"
  cp -R "$INGEST_MEMORY_DIR/." "$RAW/memory/"
  echo "  mem  $INGEST_MEMORY_DIR -> raw/memory/"
fi

echo ""
echo "Secrets scan (looks for actual key VALUES, not variable names):"
# Patterns match realistic secret shapes:
#   ghp_/gho_/ghs_/ghr_        GitHub tokens
#   sk-...                     OpenAI/Anthropic-style keys
#   eyJ...eyJ...sig            JWTs
#   BEGIN ... PRIVATE KEY      PEM keys
#   xoxb-/xoxp-                Slack tokens
SECRET_PATTERNS='(ghp_|gho_|ghs_|ghr_)[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{30,}|eyJ[A-Za-z0-9_-]{50,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY|xox[baprs]-[A-Za-z0-9-]{20,}'
HITS=$(grep -rE "$SECRET_PATTERNS" "$RAW/" 2>/dev/null || true)
if [ -n "$HITS" ]; then
  echo "$HITS" | head -5
  echo ""
  echo "WARNING: Possible secrets detected above. Review before indexing."
  exit 1
fi
echo "  clean."

# Sentinel + append-only log
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$BRAIN/.last-ingest"
echo "- $(date '+%Y-%m-%d %H:%M') — ingest — ${#INGEST_SOURCES[@]} sources" >> "$BRAIN/log.md"

echo ""
echo "Ingest complete. Raw corpus:"
du -sh "$RAW"/* 2>/dev/null || true
echo ""
echo "First run:  bash $BRAIN/bin/qmd collection add \"$RAW\" --name $BRAIN_COLLECTION"
echo "Then/after: bash $BRAIN/bin/qmd update"
