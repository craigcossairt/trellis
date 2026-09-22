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
# --write IS FOR CUTTING A RELEASE OF THE TEMPLATE, NOT FOR A COPY. It hashes
# `git ls-files`, so in a copy it records the ADOPTER's tree as though the
# template had shipped it. Measured on a fixture: a template file they had
# edited and declined went from `localonly` to `apply` - "SAFE TO TAKE" - on the
# very next sync, and their own src/app.ts turned up under "REMOVED UPSTREAM -
# decide whether to keep". The skill used to instruct exactly this as the
# recording step after an update. A copy records what it took with
# `trellis-sync.sh --apply`, which rewrites only the lines for files it fetched
# and verified. So --write refuses when this repo is not the template itself.
#
# Usage:
#   trellis-manifest.sh --write [--root DIR]   regenerate the manifest (template only)
#   trellis-manifest.sh --check [--root DIR]   validate it
#
# Exit: 0 ok / 1 problem found / 2 could not run (not a repo, no manifest, ...)
# A could-not-run is never reported as ok. "I did not check" is not "clean".
# =============================================================================
set -uo pipefail

# The carriage return is computed, not written. A literal CR byte in a
# shell script is invisible in every editor and diff, and the escape form
# is rewritten by whichever of bash, sed or perl last touched the file.
CR=$(printf '\r')

MODE=""
ROOT=""
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --write) MODE="write"; shift ;;
    --force) FORCE=1; shift ;;
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
  # Is this the template, or a copy of it? .trellis/source names the upstream;
  # if this repo's own origin is a DIFFERENT repo, this is somebody's project
  # and regenerating the manifest from its tree is the defect described above.
  # Refuse rather than warn: a warning on a destructive default is read once.
  if [ "$FORCE" -eq 0 ] && [ -f "$ROOT/.trellis/source" ]; then
    declared="$(sed -n 's/^upstream=//p' "$ROOT/.trellis/source" | tr -d "$CR" | head -1)"
    originurl="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
    origin="$(printf '%s' "$originurl" | sed -e 's#^git@[^:]*:#/#' -e 's#^[a-z+]*://[^/]*/##' -e 's#\.git$##' -e 's#^/##')"
    # The HOST has to survive the comparison. upstream= is an owner/repo pair
    # that only ever means GitHub - everything that reads it goes to
    # api.github.com or raw.githubusercontent.com - so dropping the host made
    # a GitLab remote at the same owner/repo path compare EQUAL to the
    # template and walk straight through this guard.
    _hostraw="$(printf '%s' "$originurl" | sed -n -e 's#^git@\([^:]*\):.*#\1#p' -e 's#^[a-z+]*://\([^/@]*@\)\{0,1\}\([^/]*\)/.*#\2#p' | head -1)"
    # Lowercased and with any port removed before comparison. A URL authority
    # is case-insensitive and may carry :443, so https://GitHub.com:443/o/r is
    # the SAME host as github.com - comparing it as exact text refused the
    # template's own release cut and sent the maintainer to --force, which is
    # how a guard teaches people to bypass it.
    originhost="$(printf '%s' "$_hostraw" | tr '[:upper:]' '[:lower:]' | sed 's#:[0-9]*$##')"
    if [ -n "$declared" ] && [ -n "$origin" ] &&        { [ "$originhost" != "github.com" ] || [ "$declared" != "$origin" ]; }; then
      echo "trellis-manifest: refusing --write. This looks like a COPY of $declared, not the template." >&2
      echo "  --write hashes every tracked file, so here it would record YOUR files as" >&2
      echo "  things the template shipped: your edits become 'safe to take' on the next" >&2
      echo "  sync, and your own source turns up as 'removed upstream'." >&2
      echo "  To record an update you accepted, use: trellis-sync.sh --apply <path>" >&2
      echo "  If you really are cutting a release of this template, pass --force." >&2
      exit 2
    fi
  fi
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
done < <(tr -d "$CR" < "$MANIFEST")   # a CRLF checkout must not make every path unmatchable

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
