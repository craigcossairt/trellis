#!/usr/bin/env bash
# =============================================================================
# test-trellis-sync.sh - tests for trellis-sync.sh and trellis-manifest.sh
# =============================================================================
# The whole value of sync is one distinction: "I changed this" versus "upstream
# changed this". Get that wrong in one direction and it nags about files you
# meant to change; wrong in the other and it overwrites your work. Both end with
# the tool being switched off, so every classification case here asserts the
# exact bucket rather than just "it said something".
#
# Two properties get extra weight:
#
#   - A could-not-tell is never a clean bill of health. No manifest, an empty
#     upstream manifest, an unreachable upstream: all exit 2, and 2 is not 0.
#   - The baseline is what makes a wizard-filled file applicable rather than a
#     conflict. There is a matched pair for that, WITH and WITHOUT the baseline
#     on identical inputs, so the difference is attributable to the baseline and
#     not to the fixture.
#
# Hermetic: temp repos, no network. The upstream manifest is injected with
# --upstream-manifest, which is why the classifier can be tested at all.
#
# Run:  bash bin/tests/test-trellis-sync.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SYNC="$ROOT/bin/trellis-sync.sh"
MANIFEST_SH="$ROOT/bin/trellis-manifest.sh"
for f in "$SYNC" "$MANIFEST_SH"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t trellissynctest)"
trap 'rm -rf "$TMP"' EXIT

H() { git -C "$1" hash-object "$2"; }

new_copy() { # $1 name -> a repo that looks like a template copy
  local d="$TMP/$1"
  rm -rf "$d"; mkdir -p "$d/.trellis"
  must git init -q "$d"
  must git -C "$d" config user.email 'me@example.com'
  must git -C "$d" config user.name 'Me'
  must git -C "$d" config core.autocrlf false
  printf 'upstream=example/tpl\nversion=v1.0\n' > "$d/.trellis/source"
  printf '%s' "$d"
}

OUT=""; RC=0
sync_run() { # $1 root, $2 upstream manifest, rest: extra args
  local r="$1" u="$2"; shift 2
  OUT="$(bash "$SYNC" --root "$r" --upstream-manifest "$u" --porcelain "$@" 2>&1)"; RC=$?
}
sync_human() { local r="$1" u="$2"; shift 2
  OUT="$(bash "$SYNC" --root "$r" --upstream-manifest "$u" "$@" 2>&1)"; RC=$?; }

# Assert the EXACT bucket. "it appeared somewhere" would pass for a classifier
# that put everything in one pile.
c_bucket() { # $1 name, $2 expected bucket, $3 path
  local got
  got="$(printf '%s' "$OUT" | awk -F'\t' -v p="$3" '$2 == p { print $1 }' | head -1)"
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "expected bucket '$2' for '$3', got '${got:-none}'"; fi
}
c_absent() { # $1 name, $2 path - must be in NO bucket
  local got; got="$(printf '%s' "$OUT" | awk -F'\t' -v p="$2" '$2 == p { print $1 }' | head -1)"
  if [ -z "$got" ]; then ok "$1"; else bad "$1" "expected '$2' to be unreported, got bucket '$got'"; fi
}
c_rc()  { if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "expected exit $2, got $RC ($OUT)"; fi; }
c_says(){ if printf '%s' "$OUT" | grep -qiE "$2"; then ok "$1"; else bad "$1" "output did not match /$2/: $OUT"; fi; }

# =============================================================================
echo "== A. classification =="
D="$(new_copy classify)"
printf 'same\n'   > "$D/keep.md"
printf 'orig\n'   > "$D/upstream.md"
printf 'orig\n'   > "$D/mine.md"
printf 'orig\n'   > "$D/both.md"
printf 'orig\n'   > "$D/converged.md"
printf 'orig\n'   > "$D/gone.md"
printf 'orig\n'   > "$D/deleted-here.md"
printf 'orig\n'   > "$D/with space.md"
{ for f in keep.md upstream.md mine.md both.md converged.md gone.md deleted-here.md "with space.md"; do
    printf '%s %s\n' "$(H "$D" "$D/$f")" "$f"
  done; } > "$D/.trellis/manifest"

# local divergence
printf 'mine edited\n'  > "$D/mine.md"
printf 'local edit\n'   > "$D/both.md"
printf 'converged\n'    > "$D/converged.md"
rm -f "$D/deleted-here.md"

# upstream state
U="$TMP/up-classify"
{ printf '%s keep.md\n'            "$(H "$D" "$D/keep.md")"
  printf 'a%039d upstream.md\n'    1
  printf '%s mine.md\n'            "$(printf 'orig\n' > "$TMP/o"; H "$D" "$TMP/o")"
  printf 'b%039d both.md\n'        1
  printf '%s converged.md\n'       "$(H "$D" "$D/converged.md")"
  printf '%s deleted-here.md\n'    "$(H "$D" "$TMP/o")"
  printf '%s with space.md\n'      "$(H "$D" "$TMP/o")"
  printf 'c%039d brandnew.md\n'    1
} > "$U"

sync_run "$D" "$U"
c_absent "unchanged both sides is not reported"            'keep.md'
c_bucket "upstream changed, local untouched -> apply"      apply      'upstream.md'
c_bucket "local changed, upstream unchanged -> yours"      localonly  'mine.md'
c_bucket "changed on both sides -> needs a human"          conflict   'both.md'
c_absent "both sides converged on the same content"        'converged.md'
c_bucket "upstream deleted it, we still have it"           removed    'gone.md'
c_bucket "we deleted it, upstream still ships it"          deleted    'deleted-here.md'
c_bucket "upstream added a file we do not have"            added      'brandnew.md'
c_absent "a path containing a space is handled"            'with space.md'

echo "== B. the setup baseline is what makes a filled-in file applicable =="
# Identical inputs twice; only the presence of .trellis/baseline differs, so the
# difference in outcome is attributable to the baseline and nothing else.
mk_wizard_case() { # $1 name, $2 "with"|"without" baseline
  local d; d="$(new_copy "$1")"
  printf 'AGENTS shipped\n' > "$d/AGENTS.md"
  printf '%s AGENTS.md\n' "$(H "$d" "$d/AGENTS.md")" > "$d/.trellis/manifest"
  printf 'AGENTS filled in by setup\n' > "$d/AGENTS.md"     # the wizard's write
  if [ "$2" = with ]; then
    printf '%s AGENTS.md\n' "$(H "$d" "$d/AGENTS.md")" > "$d/.trellis/baseline"
  fi
  printf '%s' "$d"
}
UP="$TMP/up-wizard"; printf 'd%039d AGENTS.md\n' 1 > "$UP"

D="$(mk_wizard_case wizard-with with)"
sync_run "$D" "$UP"
c_bucket "with a baseline, a setup-filled file is applicable"    apply    'AGENTS.md'
D="$(mk_wizard_case wizard-without without)"
sync_run "$D" "$UP"
c_bucket "without one, the same file reads as a conflict"        conflict 'AGENTS.md'

# The case that matters most, and the one the first draft of this suite did not
# have. A file setup filled in, which upstream has NOT changed, must be left
# alone. Without this, nothing stops sync offering to replace a filled-in
# AGENTS.md with the blank template - the single most damaging thing it could
# do. Found by mutation: dropping the "did upstream actually change?" half of
# the apply test broke nothing, because every other case is caught earlier by
# the converged-content check and never reaches that line.
D="$(mk_wizard_case wizard-quiet with)"
UP_SAME="$TMP/up-wizard-unchanged"
printf '%s AGENTS.md\n' "$(H "$D" "$TMP/shipped-agents")" > "$UP_SAME" 2>/dev/null || true
printf 'AGENTS shipped\n' > "$TMP/shipped-agents"
printf '%s AGENTS.md\n' "$(H "$D" "$TMP/shipped-agents")" > "$UP_SAME"
sync_run "$D" "$UP_SAME"
c_absent "a setup-filled file upstream did not change is left alone" 'AGENTS.md'
c_rc     "and that alone means there is nothing to take" 0

echo "== C. exit codes, and could-not-tell is never clean =="
D="$(new_copy exits)"
printf 'x\n' > "$D/a.md"
printf '%s a.md\n' "$(H "$D" "$D/a.md")" > "$D/.trellis/manifest"
cp "$D/.trellis/manifest" "$TMP/up-same"
sync_human "$D" "$TMP/up-same"
c_rc "nothing to take exits 0" 0
c_says "and says so in words" 'nothing to take'

printf 'e%039d a.md\n' 1 > "$TMP/up-diff"
sync_human "$D" "$TMP/up-diff"
c_rc "updates available exits 1" 1

D2="$(new_copy nomanifest)"; rm -f "$D2/.trellis/manifest"
sync_human "$D2" "$TMP/up-same"
c_rc "no local manifest exits 2, not 0" 2
c_says "and explains why rather than just failing" 'started from'

: > "$TMP/up-empty"
sync_human "$D" "$TMP/up-empty"
c_rc "an empty upstream manifest exits 2" 2
c_says "and says it would read as deleting everything" 'deleted upstream|classify every file'

sync_human "$D" "$TMP/does-not-exist"
c_rc "a missing upstream manifest exits 2" 2

OUT="$(bash "$SYNC" --root "$TMP/not-a-dir-at-all" --upstream-manifest "$TMP/up-same" 2>&1)"; RC=$?
c_rc "a root that does not exist exits 2" 2

D3="$(new_copy nosource)"
printf 'x\n' > "$D3/a.md"
printf '%s a.md\n' "$(H "$D3" "$D3/a.md")" > "$D3/.trellis/manifest"
rm -f "$D3/.trellis/source"
OUT="$(bash "$SYNC" --root "$D3" 2>&1)"; RC=$?
c_rc "no upstream recorded and none given exits 2" 2

OUT="$(bash "$SYNC" --root "$D" --bogus-flag 2>&1)"; RC=$?
c_rc "an unknown argument exits 2, never 0" 2

# =============================================================================
echo "== D. the manifest generator =="
D="$(new_copy manifest)"
printf 'one\n' > "$D/one.md"; printf 'two\n' > "$D/two.md"
must git -C "$D" add one.md two.md .trellis/source
OUT="$(bash "$MANIFEST_SH" --write --root "$D" 2>&1)"; RC=$?
c_rc "--write exits 0" 0
c_eq_lines() { local n; n="$(grep -c . "$D/.trellis/manifest")"
  if [ "$n" = "$1" ]; then ok "$2"; else bad "$2" "expected $1 entries, got $n"; fi; }
c_eq_lines 3 "--write records every tracked file"
# The manifest must be TRACKED for this to test anything: `git ls-files` only
# lists tracked files, so an untracked manifest is excluded by accident and the
# case passes with the exclusion deleted. Track it, then regenerate.
must git -C "$D" add .trellis/manifest
OUT="$(bash "$MANIFEST_SH" --write --root "$D" 2>&1)"
if grep -q ' \.trellis/manifest$' "$D/.trellis/manifest"; then
  bad "--write excludes the manifest itself even when tracked" "the manifest lists itself"
else ok "--write excludes the manifest itself even when tracked"; fi

OUT="$(bash "$MANIFEST_SH" --check --root "$D" 2>&1)"; RC=$?
c_rc "--check on a good manifest exits 0" 0

rm -f "$D/two.md"
OUT="$(bash "$MANIFEST_SH" --check --root "$D" 2>&1)"; RC=$?
c_rc "--check flags a file that has vanished" 1
c_says "and names the missing path" 'two\.md'

printf 'not-a-hash two.md\n' > "$D/.trellis/manifest"
OUT="$(bash "$MANIFEST_SH" --check --root "$D" 2>&1)"; RC=$?
c_rc "--check flags a bad hash" 1

: > "$D/.trellis/manifest"
OUT="$(bash "$MANIFEST_SH" --check --root "$D" 2>&1)"; RC=$?
c_rc "an EMPTY manifest exits 2, not 0" 2
# Not 'did not run|empty': an alternation that includes a word the broken
# version still prints cannot tell the two apart, and this case passed a
# mutation that replaced the whole message.
c_says "and says the generator did not run" 'did not run'

OUT="$(bash "$MANIFEST_SH" --check --root "$TMP" 2>&1)"; RC=$?
c_rc "a non-repo root exits 2" 2

OUT="$(bash "$MANIFEST_SH" --root "$D" 2>&1)"; RC=$?
c_rc "neither --write nor --check exits 2" 2

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
