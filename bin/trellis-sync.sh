#!/usr/bin/env bash
# =============================================================================
# trellis-sync.sh - what changed upstream, what is safe to take, and taking it
# =============================================================================
# A copy made from a GitHub template has no git ancestry with the template, so
# there is no merge base and nothing to three-way against. This compares by
# CONTENT instead, using two records:
#
#   .trellis/manifest   what the template shipped at the version you copied
#   the upstream manifest for the release you would move to
#
# With those, every path lands in exactly one bucket, and only two of them need
# a person. That is the entire point: a tool that cannot tell "I changed this"
# from "upstream changed this" either nags about files you meant to change or
# quietly overwrites them, and both make it something you stop running.
#
# APPLYING LIVES HERE, NOT IN THE SKILL, and that is the whole lesson of the
# first version. The skill told the agent to run
# `gh api .../contents/<path> > <path>`, which had two defects that no amount
# of prose around it could fix. The URL was the DEFAULT BRANCH while the
# buckets were computed from the release manifest, so the bytes written were
# not the bytes that had been classified. And the redirect truncated the
# destination before the fetch ran, so a failed fetch left an EMPTY file where
# the old one had been - measured, 42 bytes to 0 - which made the skill's own
# rule ("a failed fetch is a stop, not a skip") unreachable, because the file
# was already gone by the time the failure was known.
#
# So: one immutable commit is resolved ONCE and used for the manifest and for
# every file, every fetch is verified against its manifest hash before it is
# moved into place, and nothing is written until it is known to be correct.
#
# RECORDING ALSO LIVES HERE. It used to be `trellis-manifest.sh --write`, which
# hashes `git ls-files` - the whole working tree, the adopter's own source
# included. Running that in a copy records YOUR files as though the template
# had shipped them. Measured on a fixture: a file you edited and declined went
# from `localonly` to `apply` ("SAFE TO TAKE") on the very next run, and your
# own src/app.ts appeared under "REMOVED UPSTREAM - decide whether to keep".
# The recording step turned the tool into one that offers to delete your
# application and overwrite your edits. `--write` is for cutting a RELEASE of
# the template itself. A copy records with `--apply`, which touches only the
# lines for files it actually took.
#
# The upstream manifest is an INPUT, not something this script insists on
# fetching. `--upstream-manifest FILE` is how the tests drive it with no
# network, and it is what makes the classification testable at all.
#
# Exit: 0 nothing to take / 1 there are updates or conflicts / 2 could not tell.
# 2 never means "up to date". A failed fetch is not a clean bill of health.
#
# Usage:
#   trellis-sync.sh [--root DIR] [--upstream-manifest FILE] [--ref REF] [--porcelain]
#   trellis-sync.sh --apply PATH [--apply PATH ...] [--ref REF]
# =============================================================================
set -uo pipefail

# The carriage return is computed, not written. A literal CR byte in a
# shell script is invisible in every editor and diff, and the escape form
# is rewritten by whichever of bash, sed or perl last touched the file.
CR=$(printf '\r')

ROOT=""; UPSTREAM_MANIFEST=""; PORCELAIN=0; REF=""; DO_APPLY=0; FROM_DIR=""
APPLY_PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --upstream-manifest) UPSTREAM_MANIFEST="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --from-dir) FROM_DIR="${2:-}"; shift 2 ;;
    --porcelain) PORCELAIN=1; shift ;;
    --apply)
      [ -n "${2:-}" ] || { echo "trellis-sync: --apply needs a path" >&2; exit 2; }
      DO_APPLY=1; APPLY_PATHS[${#APPLY_PATHS[@]}]="$2"; shift 2 ;;
    -h|--help) sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "trellis-sync: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "trellis-sync: not inside a git repository, and no --root given" >&2; exit 2; }
fi
[ -d "$ROOT" ] || { echo "trellis-sync: no such directory: $ROOT" >&2; exit 2; }

LOCAL_MANIFEST="$ROOT/.trellis/manifest"
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
      upstream) UPSTREAM_REPO="$(printf '%s' "$v" | tr -d "$CR")" ;;
      version)  LOCAL_VERSION="$(printf '%s' "$v" | tr -d "$CR")" ;;
    esac
  done < "$SOURCE"
fi

work="$(mktemp -d 2>/dev/null || mktemp -d -t trellissyncwork)"
tmpdir=""
trap 'rm -rf "$work" ${tmpdir:+"$tmpdir"}' EXIT

# --- pin to ONE commit -------------------------------------------------------
# Everything downstream - the manifest AND every file byte - comes from this
# single sha. Resolving twice, or leaving either side on a moving ref, is how
# the bytes stop matching the buckets that were computed for them.
PINNED_SHA=""; PIN_NOTE=""
is_sha() { case "$1" in *[!0-9a-f]* | "") return 1 ;; esac; [ ${#1} -eq 40 ]; }
resolve_ref() { # $1 repo, $2 ref -> prints a 40-hex sha, or nothing
  local repo="$1" ref="$2" sha=""
  if is_sha "$ref"; then printf '%s' "$ref"; return 0; fi
  if command -v gh >/dev/null 2>&1; then
    sha="$(gh api "repos/$repo/commits/$ref" --jq .sha 2>/dev/null)"
  fi
  if [ -z "$sha" ] && command -v curl >/dev/null 2>&1; then
    sha="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
             "https://api.github.com/repos/$repo/commits/$ref" 2>/dev/null \
           | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' | head -1)"
  fi
  is_sha "$sha" && printf '%s' "$sha"
}

# --- obtain the upstream manifest -------------------------------------------
FETCH_NOTE=""
if [ -z "$UPSTREAM_MANIFEST" ]; then
  [ -n "$UPSTREAM_REPO" ] || {
    echo "trellis-sync: no upstream recorded in .trellis/source and no --upstream-manifest given" >&2
    exit 2; }
  tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t trellissync)"
  UPSTREAM_MANIFEST="$tmpdir/upstream-manifest"
  PINNED_SHA="$(resolve_ref "$UPSTREAM_REPO" "${REF:-HEAD}")"
  [ -n "$PINNED_SHA" ] || {
    echo "trellis-sync: could not resolve ${REF:-HEAD} in $UPSTREAM_REPO to a commit." >&2
    echo "  Refusing to compare against a moving target. That is a could-not-tell," >&2
    echo "  not a clean bill of health." >&2
    exit 2; }
  PIN_NOTE="$PINNED_SHA"
  fetched=0
  if command -v gh >/dev/null 2>&1; then
    if gh api "repos/$UPSTREAM_REPO/contents/.trellis/manifest?ref=$PINNED_SHA" \
         -H 'Accept: application/vnd.github.raw' > "$UPSTREAM_MANIFEST" 2>/dev/null \
       && [ -s "$UPSTREAM_MANIFEST" ]; then
      fetched=1; FETCH_NOTE="gh, $UPSTREAM_REPO"
    fi
  fi
  if [ "$fetched" -eq 0 ] && command -v curl >/dev/null 2>&1; then
    if curl -fsSL "https://raw.githubusercontent.com/$UPSTREAM_REPO/$PINNED_SHA/.trellis/manifest" \
         -o "$UPSTREAM_MANIFEST" 2>/dev/null && [ -s "$UPSTREAM_MANIFEST" ]; then
      fetched=1; FETCH_NOTE="curl, $UPSTREAM_REPO"
    fi
  fi
  if [ "$fetched" -eq 0 ]; then
    echo "trellis-sync: could not fetch the upstream manifest from $UPSTREAM_REPO." >&2
    echo "  Tried gh and curl. That is a could-not-tell, not you are up to date." >&2
    exit 2
  fi
fi
[ -f "$UPSTREAM_MANIFEST" ] || { echo "trellis-sync: no such manifest: $UPSTREAM_MANIFEST" >&2; exit 2; }
[ -s "$UPSTREAM_MANIFEST" ] || {
  echo "trellis-sync: the upstream manifest is empty." >&2
  echo "  An empty manifest would classify every file as deleted upstream. Refusing." >&2
  exit 2; }

# --- load ---------------------------------------------------------------------
# Sorted temp files rather than associative arrays, because bash 3.2 has none
# and it ships as /bin/bash on macOS. A construct that works on the author's
# machine and not on half its users' is not portable, it is lucky.
#
# There is deliberately NO baseline here. An earlier version read an optional
# .trellis/baseline - "what your tree looked like once setup had run" - and used
# it in place of the shipped manifest, which made a file the setup wizard filled
# in classify as `apply` rather than `conflict`. Nothing ever wrote that file,
# so nothing was broken; what it was, was armed. The moment a wizard writes one,
# every answer the adopter gave at setup becomes SAFE TO TAKE and is replaced by
# the blank template, because taking an update here is a WHOLE-FILE write. A
# baseline is only meaningful with a three-way merge. Until there is one, a
# filled-in file that upstream also changed is a conflict, and that is correct.
norm() { tr -d "$CR" < "$1" | LC_ALL=C sort -k2,2 | awk '{h=$1; $1=""; sub(/^ /,""); print $0 "\t" h}'; }

lookup() { # $1 file, $2 path -> hash or empty
  awk -F'\t' -v p="$2" '$1 == p { print $2; found=1; exit } END { if (!found) print "" }' "$1"
}

# `grep -c` on an empty file prints 0 AND exits 1, so the obvious
# `[ -f x ] && grep -c . x || echo 0` emits TWO zeros and every arithmetic
# test downstream then errors out. Same A && B || C shape shellcheck warns
# about, with a failure that looks like a counting bug rather than a shell one.
count() {
  [ -f "$1" ] || { echo 0; return 0; }
  local n; n="$(grep -c . "$1" 2>/dev/null || true)"
  echo "${n:-0}"
}

classify() {
  norm "$LOCAL_MANIFEST"    > "$work/orig"
  norm "$UPSTREAM_MANIFEST" > "$work/new"
  cut -f1 "$work/orig" "$work/new" | LC_ALL=C sort -u > "$work/paths"

  : > "$work/apply"; : > "$work/conflict"; : > "$work/localonly"
  : > "$work/added"; : > "$work/removed"; : > "$work/deleted"; : > "$work/same"

  local path o n c
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    o="$(lookup "$work/orig" "$path")"
    n="$(lookup "$work/new" "$path")"
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
    if [ "$c" = "$o" ] && [ "$n" != "$o" ]; then echo "$path" >> "$work/apply"; continue; fi
    if [ "$c" = "$o" ] && [ "$n" = "$o" ]; then echo "$path" >> "$work/same"; continue; fi
    if [ "$c" != "$o" ] && [ "$n" = "$o" ]; then echo "$path" >> "$work/localonly"; continue; fi
    echo "$path" >> "$work/conflict"
  done < "$work/paths"

  n_apply=$(count "$work/apply");     n_conflict=$(count "$work/conflict")
  n_local=$(count "$work/localonly"); n_added=$(count "$work/added")
  n_removed=$(count "$work/removed"); n_deleted=$(count "$work/deleted")
  n_actionable=$((n_apply + n_added + n_conflict + n_removed))
}

classify

# =============================================================================
# --apply
# =============================================================================
if [ "$DO_APPLY" -eq 1 ]; then
  # --from-dir takes the bytes from a local checkout of the template instead of
  # fetching them. It is what lets the tests exercise this path with no network,
  # exactly as --upstream-manifest does for classification, and it is also how
  # you apply from a clone when you are offline or behind a proxy. The hash
  # verification below runs either way: a local source is not a trusted one.
  if [ -n "$FROM_DIR" ]; then
    [ -d "$FROM_DIR" ] || { echo "trellis-sync: --from-dir is not a directory: $FROM_DIR" >&2; exit 2; }
  else
    [ -n "$UPSTREAM_REPO" ] || {
      echo "trellis-sync: --apply needs an upstream in .trellis/source" >&2; exit 2; }
    if [ -z "$PINNED_SHA" ]; then
      PINNED_SHA="$(resolve_ref "$UPSTREAM_REPO" "${REF:-HEAD}")"
      [ -n "$PINNED_SHA" ] || {
        echo "trellis-sync: --apply could not resolve ${REF:-HEAD} to a commit. Refusing." >&2
        exit 2; }
    fi
  fi
  [ -n "$tmpdir" ] || tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t trellissync)"

  # Every fetch is verified against the manifest hash BEFORE it goes anywhere
  # near the destination, and lands by rename. A half-written file is not a
  # state any version of this template was ever tested in.
  SRC_NOTE="${FROM_DIR:-$PINNED_SHA}"
  : > "$work/applied"
  failed=0
  for p in ${APPLY_PATHS[@]+"${APPLY_PATHS[@]}"}; do
    [ -n "$p" ] || continue
    want="$(lookup "$work/new" "$p")"
    if [ -z "$want" ]; then
      echo "trellis-sync: $p is not in the upstream manifest at $SRC_NOTE - not fetching." >&2
      echo "  If upstream deleted it, removing it here is your call, by hand." >&2
      failed=$((failed + 1)); continue
    fi
    # Never write to the destination. The bytes land in a temp file, and the
    # destination is not touched until they have been verified. The first
    # version of this step was `gh api ... > "<path>"` in a skill, where the
    # shell truncated the destination BEFORE the fetch ran - so a failed fetch
    # left an empty file where the old one had been, and the rule "a failed
    # fetch is a stop, not a skip" could never fire, because the file was
    # already gone by the time anyone knew it had failed.
    dest="$tmpdir/fetched"
    rm -f "$dest"
    got=0
    if [ -n "$FROM_DIR" ]; then
      [ -f "$FROM_DIR/$p" ] && cp "$FROM_DIR/$p" "$dest" && got=1
    else
      if command -v gh >/dev/null 2>&1; then
        gh api "repos/$UPSTREAM_REPO/contents/$p?ref=$PINNED_SHA" \
          -H 'Accept: application/vnd.github.raw' > "$dest" 2>/dev/null && got=1
      fi
      if [ "$got" -eq 0 ] && command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://raw.githubusercontent.com/$UPSTREAM_REPO/$PINNED_SHA/$p" \
          -o "$dest" 2>/dev/null && got=1
      fi
    fi
    if [ "$got" -eq 0 ] || [ ! -f "$dest" ]; then
      echo "trellis-sync: could not read upstream $p. Your copy is untouched." >&2
      failed=$((failed + 1)); continue
    fi
    have="$(git -C "$ROOT" hash-object "$dest" 2>/dev/null)"
    if [ "$have" != "$want" ]; then
      echo "trellis-sync: $p from $SRC_NOTE does not match the upstream manifest." >&2
      echo "  manifest says $want, fetched $have. Not writing it." >&2
      failed=$((failed + 1)); continue
    fi
    mkdir -p "$(dirname "$ROOT/$p")"
    if mv "$dest" "$ROOT/$p"; then
      printf '%s\n' "$p" >> "$work/applied"
      echo "applied $p"
    else
      echo "trellis-sync: could not write $p" >&2
      failed=$((failed + 1))
    fi
  done

  # Record ONLY what was taken. Every other manifest line is left exactly as it
  # was, so a declined update stays declined and shows up again next time, a
  # local edit stays `localonly`, and a file the template never shipped stays
  # unlisted instead of being reported as deleted upstream.
  n_applied=$(count "$work/applied")
  if [ "$n_applied" -gt 0 ]; then
    tr -d "$CR" < "$LOCAL_MANIFEST" > "$work/manifest.acc"
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      h="$(lookup "$work/new" "$p")"
      awk -v p="$p" '{ path=$0; sub(/^[^ ]* /,"",path); if (path != p) print }' \
        "$work/manifest.acc" > "$work/manifest.trim"
      printf '%s %s\n' "$h" "$p" >> "$work/manifest.trim"
      mv "$work/manifest.trim" "$work/manifest.acc"
    done < "$work/applied"
    LC_ALL=C sort -k2 "$work/manifest.acc" > "$LOCAL_MANIFEST"
    echo "recorded $n_applied path(s) in .trellis/manifest"
  fi

  if [ "$failed" -gt 0 ]; then
    echo "trellis-sync: $failed path(s) did not land. Nothing was half-written." >&2
    exit 2
  fi

  # The version in .trellis/source says which release this copy is BASED ON.
  # That is only true once nothing is outstanding, so it moves only then.
  classify
  if [ "$n_actionable" -eq 0 ] && [ -f "$SOURCE" ] && [ -n "$REF" ]; then
    sed "s|^version=.*|version=$REF|" "$SOURCE" > "$work/source.new" \
      && mv "$work/source.new" "$SOURCE" \
      && echo "this copy is now based on: $REF"
  elif [ "$n_actionable" -gt 0 ]; then
    echo "$n_actionable item(s) still outstanding, so version= in .trellis/source is unchanged."
  fi
  exit 0
fi

# =============================================================================
# report
# =============================================================================
if [ "$PORCELAIN" -eq 1 ]; then
  for k in apply conflict localonly added removed deleted; do
    while IFS= read -r p; do [ -n "$p" ] && printf '%s\t%s\n' "$k" "$p"; done < "$work/$k"
  done
else
  echo "trellis-sync"
  [ -n "$LOCAL_VERSION" ] && echo "  this copy is based on: $LOCAL_VERSION"
  [ -n "$FETCH_NOTE" ]    && echo "  upstream manifest:     $FETCH_NOTE"
  [ -n "$PIN_NOTE" ]      && echo "  pinned to commit:      $PIN_NOTE"
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
  show "$work/removed"  "NEEDS YOU - upstream deleted these, you still have them:"
  show "$work/deleted"  "DELETED HERE - you removed these; upstream still ships them:"
  if [ "$n_local" -gt 0 ]; then
    echo "YOURS - changed here, unchanged upstream ($n_local file(s)); nothing to do."
    echo
  fi
  if [ "$n_actionable" -eq 0 ]; then
    # Only ever said about a copy with nothing outstanding. Printing "you are
    # current with upstream" directly underneath a list of files is how a
    # report teaches people to stop reading it.
    if [ "$n_deleted" -gt 0 ]; then
      echo "Nothing to take. The files listed above are ones you deleted on purpose."
    else
      echo "Nothing to take. Your copy is current with upstream."
    fi
  fi
fi

[ "$n_actionable" -gt 0 ] && exit 1
exit 0
