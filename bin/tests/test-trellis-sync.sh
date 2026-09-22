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

echo "== B. a file setup filled in is never silently replaced =="
# This section used to assert the OPPOSITE, and that is the point of keeping the
# history in the comment. It read an optional .trellis/baseline - "what your tree
# looked like once setup had run" - and asserted that a filled-in AGENTS.md was
# therefore `apply`, SAFE TO TAKE. Taking an update here is a WHOLE-FILE write,
# so "safe to take" on a file holding the project name, stack and rules the
# adopter typed in at setup means replacing all of it with the blank template.
# Nothing ever wrote a baseline, so the harm was never reached - the mechanism
# was armed, not firing, which is why reading the code did not surface it and
# why the suite went green over it. A baseline is only meaningful with a
# three-way merge. There is none, so the file is a conflict, and a conflict is
# the answer that keeps the adopter's answers.
mk_wizard_case() { # $1 name, $2 "with"|"without" a stray baseline file
  local d; d="$(new_copy "$1")"
  printf 'AGENTS shipped
' > "$d/AGENTS.md"
  printf '%s AGENTS.md
' "$(H "$d" "$d/AGENTS.md")" > "$d/.trellis/manifest"
  printf 'AGENTS filled in by setup
' > "$d/AGENTS.md"     # what a wizard writes
  if [ "$2" = with ]; then
    printf '%s AGENTS.md
' "$(H "$d" "$d/AGENTS.md")" > "$d/.trellis/baseline"
  fi
  printf '%s' "$d"
}
UP="$TMP/up-wizard"; printf 'd%039d AGENTS.md
' 1 > "$UP"

D="$(mk_wizard_case wizard-without without)"
sync_run "$D" "$UP"
c_bucket "a setup-filled file upstream also changed is a conflict"  conflict 'AGENTS.md'

# The pair case, and the one that would go red if the baseline were ever wired
# back in: IDENTICAL inputs, differing only by the presence of the file. The
# outcome must not move. A mechanism that changes a verdict without anything
# else changing is the mechanism this case exists to keep out.
D="$(mk_wizard_case wizard-with with)"
sync_run "$D" "$UP"
c_bucket "a stray .trellis/baseline does not make it applicable"    conflict 'AGENTS.md'

# And the quiet case: upstream did NOT touch the file the adopter filled in, so
# there is nothing to take and nothing to ask about. It is their edit, reported
# as theirs. Without the "did upstream actually change?" half of the apply test
# this would offer to replace a filled-in AGENTS.md with the blank template,
# which is the single most damaging thing this tool could do.
D="$(mk_wizard_case wizard-quiet without)"
printf 'AGENTS shipped
' > "$TMP/shipped-agents"
UP_SAME="$TMP/up-wizard-unchanged"
printf '%s AGENTS.md
' "$(H "$D" "$TMP/shipped-agents")" > "$UP_SAME"
sync_run "$D" "$UP_SAME"
c_bucket "a setup-filled file upstream did not change is theirs"  localonly 'AGENTS.md'
c_rc     "and that alone means there is nothing to take" 0

echo "== B2. a CRLF manifest still works =="
# This is what an adopter on Windows actually receives. `* text=auto` checks the
# manifest out with CRLF unless .gitattributes pins it, every path then carries
# a trailing carriage return, nothing matches, and sync reports the ENTIRE
# template as deleted upstream. It passes when the manifest is generated locally
# and fails when it is cloned - and CI runs on Linux, so CI never sees it.
# Found by merging all the open branches together and running this suite in the
# merged tree, which is the only place a checked-out manifest existed.
to_crlf() { sed 's/$/\r/' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }
D="$(new_copy crlf)"
printf 'same\n' > "$D/keep.md"
printf 'orig\n' > "$D/changed.md"
{ printf '%s keep.md\n'    "$(H "$D" "$D/keep.md")"
  printf '%s changed.md\n' "$(H "$D" "$D/changed.md")"; } > "$D/.trellis/manifest"
to_crlf "$D/.trellis/manifest"
# The LOCAL manifest is CRLF and the UPSTREAM one is LF, which is exactly the
# real pairing: your copy was checked out by git on Windows, upstream's was
# fetched raw from the API. Making BOTH sides CRLF - the first version of this
# fixture - hides the bug, because the paths still match each other and only
# the on-disk lookup suffers. Mutation caught that: neutralising the strip in
# the classifier went 0 red until this fixture told the two sides apart.
UCRLF="$TMP/up-crlf"
{ printf '%s keep.md\n' "$(H "$D" "$D/keep.md")"
  printf 'f%039d changed.md\n' 1; } > "$UCRLF"
sync_run "$D" "$UCRLF"
c_bucket "CRLF manifests still classify a real change" apply   'changed.md'
c_absent "and an unchanged file is not reported as deleted" 'keep.md'
OUT="$(bash "$MANIFEST_SH" --check --root "$D" 2>&1)"; RC=$?
c_rc "--check accepts a CRLF manifest" 0

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

# =============================================================================
echo "== E. --apply writes only what was taken, and records only that =="
# This whole section exists because of what the FIRST version did. Applying was
# prose in the skill - fetch with `gh api ... > "<path>"`, then "regenerate the
# manifest" with `trellis-manifest.sh --write`. Both halves were wrong in ways
# no amount of rewording could fix, and neither was covered by a single case.
#
#   --write hashes `git ls-files`, i.e. the adopter's whole tree. Reproduced on
#   a fixture: a file they edited and DECLINED went localonly -> apply ("SAFE TO
#   TAKE") on the next run, and their own src/app.ts appeared under "REMOVED
#   UPSTREAM - decide whether to keep". The recording step offered to overwrite
#   their edits and delete their application.
#
#   The `>` redirect truncates the destination before the fetch runs, so a
#   failed fetch left an empty file: measured, 42 bytes to 0.
#
# So the cases below are not general coverage of a new flag. Each one is a
# specific defect that shipped, written so that reinstating the defect goes red.
apply_run() { # $1 root, $2 upstream manifest, $3 from-dir, rest: paths
  local r="$1" u="$2" f="$3"; shift 3
  local args=()
  local x; for x in "$@"; do args[${#args[@]}]="--apply"; args[${#args[@]}]="$x"; done
  OUT="$(bash "$SYNC" --root "$r" --upstream-manifest "$u" --from-dir "$f" ${args[@]+"${args[@]}"} 2>&1)"; RC=$?
}
c_file() { # $1 name, $2 path, $3 expected content
  local got; got="$(cat "$2" 2>/dev/null)"
  if [ "$got" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3' in $2, got '${got:-<empty or missing>}'"; fi
}

# One copy carrying all three shapes at once, because the bug was an
# INTERACTION: recording the taken file is what moved the other two.
D="$(new_copy applyall)"
mkdir -p "$D/src"
printf 'shipped a\n' > "$D/a.md"
printf 'shipped b\n' > "$D/b.md"
{ printf '%s a.md\n' "$(H "$D" "$D/a.md")"
  printf '%s b.md\n' "$(H "$D" "$D/b.md")"; } > "$D/.trellis/manifest"
printf 'MY edit of b\n'   > "$D/b.md"          # edited here, declined below
printf 'console.log(1)\n' > "$D/src/app.ts"    # their own code; template never shipped it

UPD="$TMP/upstream-tree"; rm -rf "$UPD"; mkdir -p "$UPD"
printf 'upstream a v2\n' > "$UPD/a.md"
printf 'shipped b\n'     > "$UPD/b.md"         # upstream did NOT touch b.md
UA="$TMP/up-apply"
{ printf '%s a.md\n' "$(H "$D" "$UPD/a.md")"
  printf '%s b.md\n' "$(H "$D" "$UPD/b.md")"; } > "$UA"

apply_run "$D" "$UA" "$UPD" 'a.md'
c_rc   "applying one file exits 0" 0
c_file "the taken file now holds the upstream bytes" "$D/a.md" 'upstream a v2'
c_file "a file that was NOT taken is left exactly alone" "$D/b.md" 'MY edit of b'

# The regression that matters most. Re-classify the same copy against the same
# upstream. Before this fix, recording rewrote the whole manifest from the
# working tree and b.md came back as `apply` - their edit, labelled safe to
# overwrite - while src/app.ts came back as `removed`.
sync_run "$D" "$UA"
c_absent "the file just taken is settled and no longer reported" 'a.md'
c_bucket "a DECLINED local edit stays theirs, it does not become applicable" localonly 'b.md'
c_absent "their own source file stays invisible, not 'removed upstream'" 'src/app.ts'
c_rc     "and nothing is outstanding" 0

# Recording is scoped: the manifest gained no line for a file the template
# never shipped. A grep for the path is the whole assertion.
if grep -q 'src/app\.ts' "$D/.trellis/manifest"; then
  bad "recording does not add the adopter's own files to the manifest" "src/app.ts is in the manifest"
else ok "recording does not add the adopter's own files to the manifest"; fi

echo "== E2. --apply refuses rather than writing something it cannot vouch for =="
# The destination must never be opened for writing before the bytes are known
# good. Each case below asserts the ORIGINAL CONTENT survives, which is the
# assertion that would have caught the truncating redirect - an exit code alone
# cannot see the difference between "refused" and "refused after emptying it".
D2="$(new_copy applyrefuse)"
printf 'shipped x\n' > "$D2/x.md"
printf '%s x.md\n' "$(H "$D2" "$D2/x.md")" > "$D2/.trellis/manifest"
BAD="$TMP/upstream-bad"; rm -rf "$BAD"; mkdir -p "$BAD"
printf 'not what the manifest promised\n' > "$BAD/x.md"
UB="$TMP/up-bad"; printf 'a%039d x.md\n' 1 > "$UB"

apply_run "$D2" "$UB" "$BAD" 'x.md'
c_rc   "content that does not match its manifest hash exits 2" 2
c_says "and says which hash it wanted" 'does not match the upstream manifest'
c_file "and the destination still holds the ORIGINAL bytes" "$D2/x.md" 'shipped x'

# A FRESH copy, deliberately. Run against $D2 this case shares a fixture with
# the one above, and a mutation that lets the mismatch through corrupts x.md
# there - so this case goes red for the PREVIOUS case's reason and the result
# reads as coverage it does not have. Found by mutation: dropping the hash
# verification turned this case red while nothing about truncation had changed.
D3="$(new_copy applymissing)"
printf 'shipped x
' > "$D3/x.md"
printf '%s x.md
' "$(H "$D3" "$D3/x.md")" > "$D3/.trellis/manifest"
MISSING="$TMP/upstream-missing"; rm -rf "$MISSING"; mkdir -p "$MISSING"
apply_run "$D3" "$UB" "$MISSING" 'x.md'
c_rc   "an unreadable upstream file exits 2" 2
c_file "and the destination is NOT truncated to empty" "$D3/x.md" 'shipped x'

# never-shipped.md EXISTS in the source dir and is absent from the manifest, so
# the fetch would succeed and only the guard can stop it. The first draft left
# the file out, which made the exit-2 assertion vacuous: deleting the guard
# still exited 2, because the read failed instead. Mutation caught that - the
# exit-code case stayed green and only the message case went red.
printf 'something upstream has but never shipped
' > "$BAD/never-shipped.md"
apply_run "$D2" "$UB" "$BAD" 'never-shipped.md'
c_rc   "a path upstream does not ship exits 2 even when readable" 2
c_says "and says removing it is the user's call" 'your call, by hand'
if [ -e "$D2/never-shipped.md" ]; then
  bad "and it is not written into the copy" "never-shipped.md was written anyway"
else ok "and it is not written into the copy"; fi

OUT="$(bash "$SYNC" --root "$D2" --apply 2>&1)"; RC=$?
c_rc "--apply with no path exits 2" 2

echo "== F. --write refuses to run inside a copy =="
# The dangerous command is now unavailable where it is dangerous. A copy's own
# origin is a different repo from the upstream recorded in .trellis/source, and
# that difference is the whole test. Refuse rather than warn: a warning printed
# on a destructive default gets read once and then scrolled past.
D="$(new_copy iscopy)"
printf 'x\n' > "$D/x.md"
must git -C "$D" add x.md .trellis/source
printf '%s x.md\n' "$(H "$D" "$D/x.md")" > "$D/.trellis/manifest"
must git -C "$D" remote add origin 'https://github.com/someone/their-project.git'

OUT="$(bash "$MANIFEST_SH" --write --root "$D" 2>&1)"; RC=$?
c_rc   "--write in a copy exits 2, it does not quietly rewrite the manifest" 2
c_says "and says what it would have done to their files" 'removed upstream|safe to take'
c_says "and names the command that IS right for a copy" 'trellis-sync.sh --apply'
# The refusal has to leave the manifest alone, not refuse after clobbering it.
c_file "and the manifest is untouched" "$D/.trellis/manifest" "$(H "$D" "$D/x.md") x.md"

OUT="$(bash "$MANIFEST_SH" --write --root "$D" --force 2>&1)"; RC=$?
c_rc "--force is the deliberate escape for cutting a release" 0

# The template itself must still be able to cut a release: same-repo origin.
D="$(new_copy istemplate)"
printf 'x\n' > "$D/x.md"
must git -C "$D" add x.md .trellis/source
must git -C "$D" remote add origin 'https://github.com/example/tpl.git'
OUT="$(bash "$MANIFEST_SH" --write --root "$D" 2>&1)"; RC=$?
c_rc "the template's own checkout can still --write without a flag" 0

# A copy with no origin at all cannot be told apart from the template, so it is
# allowed rather than refused. Stated out loud because it is the hole in this
# guard, and a hole named in a test is one somebody can close later.
D="$(new_copy noorigin)"
printf 'x\n' > "$D/x.md"
must git -C "$D" add x.md .trellis/source
OUT="$(bash "$MANIFEST_SH" --write --root "$D" 2>&1)"; RC=$?
c_rc "with no origin to compare, --write is allowed (a known hole)" 0

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
