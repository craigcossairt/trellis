#!/usr/bin/env bash
# =============================================================================
# test-check-cdpath-cd.sh - behavioral suite for bin/check-cdpath-cd.sh
# =============================================================================
# Every case runs against a THROWAWAY git repo, not this one. Scanning the live
# tree would only prove "the tree is currently clean", which is true whether or
# not the checker works. Fixtures show each rule firing and not firing.
#
# Run:  bash bin/tests/test-check-cdpath-cd.sh
# =============================================================================
set -uo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)"
CHECKER="$REPO_ROOT/bin/check-cdpath-cd.sh"
[ -f "$CHECKER" ] || { echo "cannot find $CHECKER" >&2; exit 1; }

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0; FAILED_CASES=()
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_CASES+=("$1"); printf '  FAIL %s\n' "$1"; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t cdpathcheck)"
# A plain trap, not a function: shellcheck versions disagree on which code a
# trap-only function earns, and a finding that differs by version is noise.
trap 'rm -rf "$TMP"' EXIT

# new_fixture <body-of-bin/subject.sh> -> sets FIX to a committed repo dir
FIX=""
N=0
new_fixture() {
  N=$((N + 1))
  FIX="$TMP/fix$N"
  mkdir -p "$FIX/bin" "$FIX/.githooks"
  cp "$CHECKER" "$FIX/bin/"
  printf '#!/usr/bin/env bash\necho hook\n' > "$FIX/.githooks/pre-push"
  printf '%s\n' "$1" > "$FIX/bin/subject.sh"
  ( cd "$FIX" \
    && git init -q . \
    && git config user.email t@example.com && git config user.name t \
    && git config commit.gpgsign false && git config core.autocrlf false \
    && git add -A && git commit -qm f ) >/dev/null 2>&1 \
    || { echo "FIXTURE FAILED: could not build $FIX" >&2; exit 1; }
}

RC=0; OUT=""
scan() { # [mode] -> sets RC and OUT (stdout+stderr)
  RC=0
  OUT=$( cd "$FIX" && bash bin/check-cdpath-cd.sh "$@" 2>&1 ) || RC=$?
}

# expect_rc <label> <want-rc> <subject-body>
expect_rc() {
  new_fixture "$3"; scan
  if [ "$RC" = "$2" ]; then ok "$1"
  else bad "$1 (want exit $2, got $RC)"; printf '%s\n' "$OUT" | sed 's/^/        /' | tail -4; fi
}

# Assembled so this suite's own lines are not a literal instance of what the
# checker forbids (it scans bin/tests/ too). Single-quoted on purpose: these
# are the literal script text under test, not expansions.
# shellcheck disable=SC2016
D='$(dirname "${BASH_SOURCE[0]}")'
# shellcheck disable=SC2016
Z='$(dirname "$0")'
# shellcheck disable=SC2016
P='${BASH_SOURCE[0]%/*}'
# shellcheck disable=SC2016
Q='${0%/*}'

echo "check-cdpath-cd.sh"
echo "== the forbidden shape fires =="
expect_rc 'unguarded BASH_SOURCE capture'        1 "X=\"\$(cd \"$D\" && pwd)\""
expect_rc 'unguarded capture, parent dir'        1 "X=\"\$(cd \"$D/..\" && pwd)\""
expect_rc 'unguarded capture with a space'       1 "X=\"\$( cd \"$D\" && pwd )\""
expect_rc 'unguarded dollar-0 capture'           1 "X=\$(cd \"$Z\" && pwd)"
expect_rc 'bare cd into the script dir'          1 "cd \"$Z/..\""
expect_rc 'unguarded cd with --'                 1 "X=\"\$(cd -- \"$D\" && pwd)\""
expect_rc 'a NON-empty CDPATH is not a guard'    1 "X=\"\$(CDPATH=. cd \"$D\" && pwd)\""
expect_rc 'code before a trailing comment fires' 1 "cd \"$Z\"  # moving"
# `cd -P` is the symlink-safe idiom and echoes through CDPATH exactly like a
# plain cd, so it must not slip past.
expect_rc 'unguarded cd -P'                      1 "X=\"\$(cd -P \"$D\" && pwd)\""
expect_rc 'unguarded cd -P --'                   1 "X=\"\$(cd -P -- \"$D\" && pwd)\""
# The parameter-expansion spelling of dirname.
expect_rc 'unguarded BASH_SOURCE %/* form'       1 "X=\"\$(cd \"$P\" && pwd)\""
expect_rc 'unguarded dollar-0 %/* form'          1 "X=\"\$(cd \"$Q/..\" && pwd)\""
# One guarded and one unguarded cd on the SAME line: counting "is there a guard
# on this line" instead of comparing counts would wave the second one through.
expect_rc 'a guarded cd does not cover a second, unguarded one' 1 \
  "A=\"\$(CDPATH='' cd -- \"$D\" >/dev/null && pwd)\"; B=\"\$(cd \"$Z\" && pwd)\""

echo "== the guarded and unrelated shapes do not =="
expect_rc "guarded with CDPATH=''"               0 "X=\"\$(CDPATH='' cd -- \"$D\" >/dev/null && pwd)\""
expect_rc 'guarded with CDPATH=""'               0 "X=\"\$(CDPATH=\"\" cd -- \"$D\" >/dev/null && pwd)\""
expect_rc 'guarded with a bare CDPATH='          0 "cd_to() { CDPATH= cd \"$Z\"; }"
expect_rc 'guarded cd -P'                        0 "X=\"\$(CDPATH='' cd -P -- \"$D\" >/dev/null && pwd)\""
expect_rc 'guarded %/* form'                     0 "X=\"\$(CDPATH='' cd -- \"$P\" >/dev/null && pwd)\""
# shellcheck disable=SC2016
expect_rc 'cd into an absolute variable'         0 'X="$(cd "$HOOK_DIR/.." && pwd)"'
expect_rc 'pure comment line'                    0 "# e.g. X=\"\$(cd \"$D\" && pwd)\""
expect_rc 'opt-out with a reason'                0 "cd \"$Z\"  # cdpath-ok: CDPATH is unset at the top of this script"
expect_rc 'opt-out WITHOUT a reason still fires' 1 "cd \"$Z\"  # cdpath-ok:"
# The marker only counts as a real shell comment. Inside quoted text it is data,
# and a line carrying it that way must not be waved through. The marker sits
# after a SPACE inside the quotes on purpose: directly after the opening quote
# it fails the "# must start a word" rule on its own, and the case would pass
# with the quote stripping removed (measured: 0 red until this was changed).
expect_rc 'marker inside double quotes fires'    1 "echo \"see # cdpath-ok: not a comment\"; cd \"$Z\""
expect_rc 'marker inside single quotes fires'    1 "echo 'see # cdpath-ok: not a comment'; cd \"$Z\""
# `#` glued to a word is not a comment in shell either.
expect_rc 'marker glued to a word fires'         1 "cd \"$Z\"#cdpath-ok: glued"

echo "== the surface includes .githooks/* =="
# A git hook has no .sh extension, and git runs it from wherever, so it is the
# file most likely to be missed by an extension-only scan.
new_fixture 'echo fine'
printf '#!/usr/bin/env bash\nX="%s(cd "%s" && pwd)"\n' '$' "$Z" > "$FIX/.githooks/pre-push"
( cd "$FIX" && git add -A && git commit -qm hook ) >/dev/null 2>&1
scan --list
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx '.githooks/pre-push:2'; then ok 'a hook under .githooks/ is scanned'
else bad "a hook under .githooks/ is scanned (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/        /' | tail -4; fi

echo "== reporting =="
new_fixture "X=\"\$(cd \"$D\" && pwd)\""
scan --list
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qx 'bin/subject.sh:1'; then ok '--list names file:line and exits 0'
else bad "--list names file:line and exits 0 (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/        /' | tail -4; fi
scan
# The failure is an instruction, so its text is asserted: it must show the
# guarded form to copy, not just say "bad".
if printf '%s\n' "$OUT" | grep -qF "CDPATH='' cd --"; then ok 'the failure names the guarded form'
else bad 'the failure names the guarded form'; fi
if printf '%s\n' "$OUT" | grep -q 'bin/subject.sh:1'; then ok 'the failure names the offending file:line'
else bad 'the failure names the offending file:line'; fi

new_fixture 'echo fine'
scan --bogus
if [ "$RC" = 2 ]; then ok 'an unknown mode exits 2'; else bad "an unknown mode exits 2 (got $RC)"; fi

echo "== could-not-scan is never clean =="
NOREPO="$TMP/norepo"
mkdir -p "$NOREPO/bin"; cp "$CHECKER" "$NOREPO/bin/"
rc=0; ( cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TMP" bash bin/check-cdpath-cd.sh >/dev/null 2>&1 ) || rc=$?
if [ "$rc" = 2 ]; then ok 'outside a git repo exits 2'; else bad "outside a git repo exits 2 (got $rc)"; fi

# A repo with nothing tracked has an EMPTY surface. That is a scan with no
# input, not a clean scan, and it must not report a pass.
EMPTYREPO="$TMP/emptyrepo"
mkdir -p "$EMPTYREPO/bin"; cp "$CHECKER" "$EMPTYREPO/bin/"
( cd "$EMPTYREPO" && git init -q . ) >/dev/null 2>&1
rc=0; ( cd "$EMPTYREPO" && bash bin/check-cdpath-cd.sh >/dev/null 2>&1 ) || rc=$?
if [ "$rc" = 2 ]; then ok 'an empty surface exits 2'; else bad "an empty surface exits 2 (got $rc)"; fi

# git itself failing to list the surface. A shim on PATH fails only ls-files,
# so everything else (rev-parse, which locates the repo) still works and the
# case reaches the listing step.
new_fixture "X=\"\$(cd \"$D\" && pwd)\""
REAL_GIT="$(command -v git)"
LSF="$TMP/lsf-shim"; mkdir -p "$LSF"
cat > "$LSF/git" <<EOS
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "ls-files" ]; then : > "$TMP/.lsf-fired"; exit 128; fi
done
exec "$REAL_GIT" "\$@"
EOS
chmod +x "$LSF/git"
rm -f "$TMP/.lsf-fired"
RC=0; OUT=$( cd "$FIX" && PATH="$LSF:$PATH" bash bin/check-cdpath-cd.sh 2>&1 ) || RC=$?
if [ "$RC" = 2 ]; then ok 'a failed surface listing exits 2'; else bad "a failed surface listing exits 2 (got $RC)"; fi
if [ -e "$TMP/.lsf-fired" ]; then ok 'fixture sanity: the ls-files shim fired'
else bad 'fixture sanity: the ls-files shim fired'; fi

# A file on the surface that cannot be read is a hole in the scan, and the hole
# is exactly where an unguarded cd could sit.
new_fixture 'echo fine'
rm -f "$FIX/bin/subject.sh"   # tracked, listed, and now unreadable
scan
if [ "$RC" = 2 ]; then ok 'an unreadable file on the surface exits 2'; else bad "an unreadable file on the surface exits 2 (got $RC)"; fi

echo "== run by a RELATIVE path with CDPATH exported =="
# Every case above already runs the checker relatively (`bash bin/...` from the
# fixture root). With CDPATH exported, the checker must still find its repo and
# its site: it is the bug this checker exists to catch, so it must survive it.
new_fixture "X=\"\$(cd \"$D\" && pwd)\""
RC=0; OUT=$( cd "$FIX" && CDPATH=. bash bin/check-cdpath-cd.sh 2>&1 ) || RC=$?
if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'bin/subject.sh:1'; then ok 'relative + CDPATH=.: still finds the site'
else bad "relative + CDPATH=.: still finds the site (rc=$RC)"; printf '%s\n' "$OUT" | sed 's/^/        /' | tail -3; fi

echo "== the checker passes its own scan =="
# The fixture's surface includes bin/check-cdpath-cd.sh itself, so a clean
# subject proves the checker's own text is clean under its own rule.
expect_rc 'self-scan is clean' 0 'echo fine'

echo
echo "passed $PASS, failed $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAILED_CASES[@]}"
  exit 1
fi
exit 0
