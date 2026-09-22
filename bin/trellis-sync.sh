#!/usr/bin/env bash
# =============================================================================
# trellis-sync.sh - what changed upstream, and what is safe to take
# =============================================================================
# A copy made from a GitHub template has no git ancestry with the template, so
# there is no merge base and nothing to three-way against. This compares by
# CONTENT instead, using three records:
#
#   .trellis/manifest   what the template shipped at the version you copied
#   .trellis/baseline   what your tree looked like once setup had run (optional;
#                       written by the setup wizard, falls back to the manifest)
#   the upstream manifest for the release you would move to
#
# With those, every path lands in exactly one bucket, and only one of them needs
# a person. That is the entire point: a tool that cannot tell "I changed this"
# from "upstream changed this" either nags about files you meant to change or
# quietly overwrites them, and both make it something you stop running.
#
# The upstream manifest is an INPUT, not something this script insists on
# fetching. `--upstream-manifest FILE` is how the tests drive it with no
# network, and it is what makes the classification testable at all.
#
# Exit: 0 nothing to take / 1 there are updates or conflicts / 2 could not tell.
# 2 never means "up to date". A failed fetch is not a clean bill of health.
#
# Usage:
#   trellis-sync.sh [--root DIR] [--upstream-manifest FILE] [--porcelain]
# =============================================================================
set -uo pipefail

# The carriage return is computed, not written. A literal CR byte in a
# shell script is invisible in every editor and diff, and the escape form
# is rewritten by whichever of bash, sed or perl last touched the file.
CR=$(printf '\r')

ROOT=""; UPSTREAM_MANIFEST=""; PORCELAIN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --upstream-manifest) UPSTREAM_MANIFEST="${2:-}"; shift 2 ;;
    --porcelain) PORCELAIN=1; shift ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "trellis-sync: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "trellis-sync: not inside a git repository, and no --root given" >&2; exit 2; }
fi
[ -d "$ROOT" ] || { echo "trellis-sync: no such directory: $ROOT" >&2; exit 2; }

LOCAL_MANIFEST="$ROOT/.trellis/manifest"
BASELINE="$ROOT/.trellis/baseline"
SOURCE="$ROOT/.trellis/source"

[ -f "$LOCAL_MANIFEST" ] || {
  echo "trellis-sync: no .trellis/manifest in $ROOT." >&2
  echo "  Without a record of what this copy started from, nothing here can be" >&2
  echo "  told apart from an ordinary local edit. Not guessing." >&2
  exit 2; }

# --- where upstream is -------------------------------------------------------
UPSTREAM_REPO=""; LOCAL_VERSION=""
if [ -f "$SOURCE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      upstream) UPSTREAM_REPO="$v" ;;
      version)  LOCAL_VERSION="$v" ;;
    esac
  done < "$SOURCE"
fi

# --- obtain the upstream manifest -------------------------------------------
FETCH_NOTE=""
if [ -z "$UPSTREAM_MANIFEST" ]; then
  [ -n "$UPSTREAM_REPO" ] || {
    echo "trellis-sync: no upstream recorded in .trellis/source and no --upstream-manifest given" >&2
    exit 2; }
  tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t trellissync)"
  trap 'rm -rf "$tmpdir"' EXIT
  UPSTREAM_MANIFEST="$tmpdir/upstream-manifest"
  fetched=0
  if command -v gh >/dev/null 2>&1; then
    if gh api "repos/$UPSTREAM_REPO/contents/.trellis/manifest" \
         -H 'Accept: application/vnd.github.raw' > "$UPSTREAM_MANIFEST" 2>/dev/null \
       && [ -s "$UPSTREAM_MANIFEST" ]; then
      fetched=1; FETCH_NOTE="fetched via gh from $UPSTREAM_REPO"
    fi
  fi
  if [ "$fetched" -eq 0 ] && command -v curl >/dev/null 2>&1; then
    if curl -fsSL "https://raw.githubusercontent.com/$UPSTREAM_REPO/HEAD/.trellis/manifest" \
         -o "$UPSTREAM_MANIFEST" 2>/dev/null && [ -s "$UPSTREAM_MANIFEST" ]; then
      fetched=1; FETCH_NOTE="fetched via curl from $UPSTREAM_REPO"
    fi
  fi
  if [ "$fetched" -eq 0 ]; then
    echo "trellis-sync: could not fetch the upstream manifest from $UPSTREAM_REPO." >&2
    echo "  Tried gh and curl. This is 'I do not know', not 'you are up to date'." >&2
    exit 2
  fi
fi
[ -f "$UPSTREAM_MANIFEST" ] || { echo "trellis-sync: no such manifest: $UPSTREAM_MANIFEST" >&2; exit 2; }
[ -s "$UPSTREAM_MANIFEST" ] || {
  echo "trellis-sync: the upstream manifest is empty." >&2
  echo "  An empty manifest would classify every file as deleted upstream. Refusing." >&2
  exit 2; }

# --- load ---------------------------------------------------------------------
# Three associative arrays would be the obvious shape; this uses sorted temp
# files and `join` instead, because bash 3.2 has no associative arrays and it
# ships as /bin/bash on macOS. A construct that works on the author's machine
# and not on half its users' is not portable, it is lucky.
work="$(mktemp -d 2>/dev/null || mktemp -d -t trellissyncwork)"
trap 'rm -rf "$work" ${tmpdir:+"$tmpdir"}' EXIT

norm() { tr -d "$CR" < "$1" | LC_ALL=C sort -k2,2 | awk '{h=$1; $1=""; sub(/^ /,""); print $0 "\t" h}'; }
norm "$LOCAL_MANIFEST"    > "$work/orig"
norm "$UPSTREAM_MANIFEST" > "$work/new"
if [ -f "$BASELINE" ] && [ -s "$BASELINE" ]; then
  norm "$BASELINE" > "$work/base"; BASELINE_USED="yes"
else
  cp "$work/orig" "$work/base"; BASELINE_USED="no (falling back to the shipped manifest)"
fi

lookup() { # $1 file, $2 path -> hash or empty
  awk -F'\t' -v p="$2" '$1 == p { print $2; found=1; exit } END { if (!found) print "" }' "$1"
}

cut -f1 "$work/orig" "$work/new" | LC_ALL=C sort -u > "$work/paths"

: > "$work/apply"; : > "$work/conflict"; : > "$work/localonly"
: > "$work/added"; : > "$work/removed"; : > "$work/deleted"; : > "$work/same"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  o="$(lookup "$work/orig" "$path")"
  n="$(lookup "$work/new" "$path")"
  b="$(lookup "$work/base" "$path")"
  [ -n "$b" ] || b="$o"
  if [ -e "$ROOT/$path" ]; then
    c="$(git -C "$ROOT" hash-object "$ROOT/$path" 2>/dev/null)"
  else
    c=""
  fi

  if [ -z "$o" ] && [ -n "$n" ]; then
    if [ -z "$c" ]; then echo "$path" >> "$work/added"
    elif [ "$c" = "$n" ]; then echo "$path" >> "$work/same"
    else echo "$path" >> "$work/conflict"; fi
    continue
  fi
  if [ -n "$o" ] && [ -z "$n" ]; then
    [ -n "$c" ] && echo "$path" >> "$work/removed"
    continue
  fi
  if [ -z "$c" ]; then echo "$path" >> "$work/deleted"; continue; fi
  if [ "$c" = "$n" ]; then echo "$path" >> "$work/same"; continue; fi
  if [ "$c" = "$b" ] && [ "$n" != "$o" ]; then echo "$path" >> "$work/apply"; continue; fi
  if [ "$c" = "$b" ] && [ "$n" = "$o" ]; then echo "$path" >> "$work/same"; continue; fi
  if [ "$c" != "$b" ] && [ "$n" = "$o" ]; then echo "$path" >> "$work/localonly"; continue; fi
  echo "$path" >> "$work/conflict"
done < "$work/paths"

# `grep -c` on an empty file prints 0 AND exits 1, so the obvious
# `[ -f x ] && grep -c . x || echo 0` emits TWO zeros and every arithmetic
# test downstream then errors out. Same A && B || C shape shellcheck warns
# about, with a failure that looks like a counting bug rather than a shell one.
count() {
  [ -f "$1" ] || { echo 0; return 0; }
  local n; n="$(grep -c . "$1" 2>/dev/null || true)"
  echo "${n:-0}"
}
n_apply=$(count "$work/apply");     n_conflict=$(count "$work/conflict")
n_local=$(count "$work/localonly"); n_added=$(count "$work/added")
n_removed=$(count "$work/removed")

if [ "$PORCELAIN" -eq 1 ]; then
  for k in apply conflict localonly added removed deleted; do
    while IFS= read -r p; do [ -n "$p" ] && printf '%s\t%s\n' "$k" "$p"; done < "$work/$k"
  done
else
  echo "trellis-sync"
  [ -n "$LOCAL_VERSION" ] && echo "  this copy is based on: $LOCAL_VERSION"
  [ -n "$FETCH_NOTE" ]    && echo "  upstream manifest:     $FETCH_NOTE"
  echo "  setup baseline used:   $BASELINE_USED"
  echo
  show() { # $1 file, $2 heading
    [ "$(count "$1")" -gt 0 ] || return 0
    echo "$2"
    sed 's/^/    /' "$1"
    echo
  }
  show "$work/apply"    "SAFE TO TAKE - upstream changed these, you have not:"
  show "$work/added"    "NEW UPSTREAM FILES - not present in your copy:"
  show "$work/conflict" "NEEDS YOU - changed both upstream and here:"
  show "$work/removed"  "REMOVED UPSTREAM - still present in your copy, decide whether to keep:"
  show "$work/deleted"  "DELETED HERE - you removed these; upstream still ships them:"
  if [ "$n_local" -gt 0 ]; then
    echo "YOURS - changed here, unchanged upstream ($n_local file(s)); nothing to do."
    echo
  fi
  if [ $((n_apply + n_added + n_conflict + n_removed)) -eq 0 ]; then
    echo "Nothing to take. Your copy is current with upstream."
  fi
fi

[ $((n_apply + n_added + n_conflict + n_removed)) -gt 0 ] && exit 1
exit 0
