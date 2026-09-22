#!/usr/bin/env bash
# =============================================================================
# trellis-manifest.sh - write or check .trellis/manifest
# =============================================================================
# The manifest records what THIS RELEASE of the template shipped: one line of
# `<blob-hash> <path>` per tracked file. A copy made from the template keeps it,
# which is what later lets `trellis-sync.sh` tell three things apart that
# otherwise look identical:
#
#   - a file you have never touched
#   - a file you deliberately changed
#   - a file upstream changed since you copied it
#
# Without a record of what you started from there is no way to distinguish the
# first two, and a sync tool that cannot do that either nags about files you
# meant to change or silently overwrites them.
#
# The hash is `git hash-object`, so it matches `git ls-tree` exactly and is
# stable across platforms regardless of how the working tree checked out. That
# matters on Windows, where a text file on disk has CRLF endings while the blob
# git recorded has LF - comparing file bytes would report drift on every file.
#
# The manifest describes a RELEASE, not the current state of main. It is
# regenerated when a release is cut, not on every commit, so CI deliberately
# does NOT require it to match the working tree - only that it is well formed
# and that nothing it names has vanished.
#
# Usage:
#   trellis-manifest.sh --write [--root DIR]   regenerate the manifest
#   trellis-manifest.sh --check [--root DIR]   validate it
#
# Exit: 0 ok / 1 problem found / 2 could not run (not a repo, no manifest, ...)
# A could-not-run is never reported as ok. "I did not check" is not "clean".
# =============================================================================
set -uo pipefail

MODE=""
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --write) MODE="write"; shift ;;
    --check) MODE="check"; shift ;;
    --root)  ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "trellis-manifest: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "trellis-manifest: need --write or --check" >&2; exit 2; }

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "trellis-manifest: not inside a git repository, and no --root given" >&2
    exit 2
  }
fi
[ -d "$ROOT" ] || { echo "trellis-manifest: no such directory: $ROOT" >&2; exit 2; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "trellis-manifest: $ROOT is not a git repository" >&2
  exit 2
}

MANIFEST="$ROOT/.trellis/manifest"

# Files the manifest deliberately does not cover. .trellis/manifest cannot
# contain its own hash, and .trellis/baseline is per-copy state written by the
# setup wizard rather than something the template ships.
excluded() {
  case "$1" in
    .trellis/manifest|.trellis/baseline) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$MODE" = "write" ]; then
  mkdir -p "$ROOT/.trellis"
  tmp="$MANIFEST.tmp.$$"
  : > "$tmp"
  # -z and a NUL-delimited read, so a path containing a space or a newline is
  # handled rather than silently split into two entries.
  while IFS= read -r -d '' path; do
    excluded "$path" && continue
    printf '%s %s\n' "$(git -C "$ROOT" hash-object "$ROOT/$path")" "$path" >> "$tmp"
  done < <(git -C "$ROOT" ls-files -z)
  LC_ALL=C sort -k2 "$tmp" > "$MANIFEST"
  rm -f "$tmp"
  echo "wrote $(wc -l < "$MANIFEST" | tr -d ' ') entries to .trellis/manifest"
  exit 0
fi

# --- check -------------------------------------------------------------------
[ -f "$MANIFEST" ] || { echo "trellis-manifest: no .trellis/manifest to check" >&2; exit 2; }

problems=0
lineno=0
while IFS= read -r line; do
  lineno=$((lineno + 1))
  [ -n "$line" ] || continue
  hash="${line%% *}"
  path="${line#* }"
  if [ "$hash" = "$line" ] || [ -z "$path" ]; then
    echo "malformed line $lineno: $line"
    problems=$((problems + 1)); continue
  fi
  case "$hash" in
    *[!0-9a-f]* | "") echo "line $lineno: '$hash' is not a blob hash"; problems=$((problems + 1)); continue ;;
  esac
  if [ ! -e "$ROOT/$path" ]; then
    echo "line $lineno: manifest names a file that no longer exists: $path"
    problems=$((problems + 1))
  fi
done < "$MANIFEST"

if [ "$lineno" -eq 0 ]; then
  # An empty manifest is a could-not-have-run result, not a clean one: a real
  # template always ships files. Reporting it as ok is how a broken generator
  # becomes invisible.
  echo "trellis-manifest: manifest is empty - the generator did not run, or ran against an empty tree" >&2
  exit 2
fi

if [ "$problems" -gt 0 ]; then
  echo "trellis-manifest: $problems problem(s) in .trellis/manifest"
  exit 1
fi
echo "trellis-manifest: $lineno entries, all well formed and present"
exit 0
