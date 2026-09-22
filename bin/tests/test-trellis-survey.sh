#!/usr/bin/env bash
# =============================================================================
# test-trellis-survey.sh - tests for trellis-survey.sh
# =============================================================================
# The survey exists to notice things that look exactly like a working setup: a
# hook on disk that nothing invokes, a hook settings.json invokes that is not on
# disk, a git hook without its executable bit, a router pointing at a deleted
# skill. Every one of those is silent in normal use, so the only thing standing
# between them and going unnoticed is this file.
#
# Two properties get extra weight:
#
#   - A survey that examined nothing exits 2, never 0. "I found no problems" and
#     "I could not look" are different answers.
#   - Every finding it COUNTS it must also PRINT. The first version counted five
#     and printed two, because `case "$kind" in $1)` does not treat a `|` from a
#     variable as alternation. A total that disagrees with the body is how a
#     report trains people to skim it, so there is a case asserting they match.
#
# Hermetic: temp trees, no network.
#
# Run:  bash bin/tests/test-trellis-survey.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SURVEY="$ROOT/bin/trellis-survey.sh"
[ -f "$SURVEY" ] || { echo "missing $SURVEY" >&2; exit 1; }

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t trellissurveytest)"
trap 'rm -rf "$TMP"' EXIT

OUT=""; RC=0
run()  { OUT="$(bash "$SURVEY" --root "$1" 2>&1)"; RC=$?; }
runp() { OUT="$(bash "$SURVEY" --root "$1" --porcelain 2>&1)"; RC=$?; }

c_rc()   { if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "expected exit $2, got $RC ($OUT)"; fi; }
c_says() { if printf '%s' "$OUT" | grep -qE "$2"; then ok "$1"; else bad "$1" "no match /$2/ in: $OUT"; fi; }
c_not()  { if printf '%s' "$OUT" | grep -qE "$2"; then bad "$1" "did not expect /$2/ in: $OUT"; else ok "$1"; fi; }
c_kind() { # $1 name, $2 expected kind, $3 subject
  local got; got="$(printf '%s' "$OUT" | awk -F'\t' -v s="$3" '$2 == s { print $1 }' | head -1)"
  if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "expected kind '$2' for '$3', got '${got:-none}'"; fi
}

# A copy, not the template: origin is somebody else's repo, so the setup
# completeness section is live.
new_copy() { # $1 name
  local d="$TMP/$1"
  rm -rf "$d"; mkdir -p "$d/.claude/hooks" "$d/.claude/skills" "$d/.cursor/skills" "$d/.trellis"
  must git init -q "$d"
  must git -C "$d" config user.email 'me@example.com'
  must git -C "$d" config user.name 'Me'
  must git -C "$d" remote add origin 'https://github.com/someone/their-app.git'
  printf 'upstream=example/tpl\nversion=v1.0\n' > "$d/.trellis/source"
  : > "$d/.trellis/manifest"
  printf '{ "hooks": {} }\n' > "$d/.claude/settings.json"
  printf '%s' "$d"
}
add_skill()  { mkdir -p "$1/.claude/skills/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/.claude/skills/$2/SKILL.md"; }
add_router() { mkdir -p "$1/.cursor/skills/$2"; printf -- '---\nname: %s\n---\n' "$2" > "$1/.cursor/skills/$2/SKILL.md"; }

# =============================================================================
echo "== A. a clean copy is clean =="
D="$(new_copy clean)"
add_skill "$D" alpha; add_router "$D" alpha
printf 'x\n' > "$D/AGENTS.md"
run "$D"
c_rc   "a consistent copy exits 0" 0
c_says "and says so in words" 'Nothing to report'

echo "== B. harness coverage in both directions =="
D="$(new_copy routers)"
add_skill "$D" haslr; add_router "$D" haslr
add_skill "$D" noroute                 # skill with no router
add_router "$D" ghost                  # router with no skill
runp "$D"
c_rc   "findings exit 1" 1
c_kind "a skill with no router is reported"        skill-no-router  'noroute'
c_kind "a router with no skill is reported"        router-dangling  'ghost'
c_not  "and a matched pair is not reported"        'haslr'

echo "== C. hooks: on disk vs wired =="
# The two directions are different failures. An unwired script is inert and
# harmless; a wired script that is absent means the harness calls something on
# every matching tool call and nothing happens - and nothing says so.
D="$(new_copy hooks)"
printf '#!/usr/bin/env bash\n' > "$D/.claude/hooks/orphan.sh"
printf '#!/usr/bin/env bash\n' > "$D/.claude/hooks/wired.sh"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "hooks": [
  { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/wired.sh\"" },
  { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/vanished.sh\"" }
] } ] } }
JSON
runp "$D"
c_kind "a script nothing invokes is reported inert"     hook-unwired ".claude/hooks/orphan.sh"
c_kind "a script settings.json invokes but is absent"   hook-missing 'vanished.sh'
c_not  "and a correctly wired hook is not reported"     'wired\.sh'

run "$D"
c_says "the absent hook is reported under NOT RUNNING" 'NOT RUNNING'
c_says "and the inert one under a different heading"   'PRESENT BUT INERT'

echo "== D. git hooks that git will silently skip =="
D="$(new_copy githooks)"
mkdir -p "$D/.githooks"
printf '#!/usr/bin/env bash\n' > "$D/.githooks/pre-push"
chmod +x "$D/.githooks/pre-push" 2>/dev/null
runp "$D"
c_kind "hooksPath unset means none of them run" githooks-not-installed 'core.hooksPath'
must git -C "$D" config core.hooksPath .githooks
# The probe has to test the direction the case actually needs. Checking only
# that chmod +x sticks passes on MSYS/NTFS, where +x sticks and -x does not -
# so the case ran, could never go red, and a skipped check reported as a pass.
probe="$TMP/xprobe"; printf '#!/bin/sh\n' > "$probe"
chmod +x "$probe" 2>/dev/null; probe_on=0;  [ -x "$probe" ] && probe_on=1
chmod -x "$probe" 2>/dev/null; probe_off=0; [ -x "$probe" ] || probe_off=1
if [ "$probe_on" = 1 ] && [ "$probe_off" = 1 ]; then
  chmod -x "$D/.githooks/pre-push"
  runp "$D"
  c_kind "a hook without its exec bit is reported" githook-not-executable '.githooks/pre-push'
else
  echo "  SKIP one exec-bit case: this filesystem does not carry the mode both ways"
fi

echo "== E. setup completeness, and the template's own exemption =="
D="$(new_copy fillin)"
printf 'name: <!-- FILL IN -->\nstack: <!-- FILL IN -->\n' > "$D/AGENTS.md"
runp "$D"
c_kind "markers left in a copy are a finding" setup-incomplete 'AGENTS.md'
# Same tree, but now this repo IS the upstream it names. The markers are the
# shipped product there, and reporting them would make the command permanently
# noisy in the one repo whose maintainer runs it most.
must git -C "$D" remote set-url origin 'https://github.com/example/tpl.git'
runp "$D"
c_not "the template itself is exempt from its own markers" 'setup-incomplete'
# ... but only on the right host. Same path, different host, is not the template.
must git -C "$D" remote set-url origin 'https://gitlab.com/example/tpl.git'
runp "$D"
c_kind "and the exemption requires the host, not just the path" setup-incomplete 'AGENTS.md'

echo "== F. the total must equal what was printed =="
# The first version counted five findings and printed two: `case "$kind" in $1)`
# treats a `|` arriving from a variable as a literal character, so every
# multi-kind section matched nothing while the total still counted them. A
# report whose total disagrees with its body teaches people to skim it.
D="$(new_copy totals)"
add_skill "$D" lonely                       # skill-no-router
add_router "$D" phantom                     # router-dangling
mkdir -p "$D/.githooks"; printf '#!/usr/bin/env bash\n' > "$D/.githooks/pre-push"
printf '<!-- FILL IN -->\n' > "$D/AGENTS.md"
printf '#!/usr/bin/env bash\n' > "$D/.claude/hooks/inert.sh"
runp "$D"; porcelain_n="$(printf '%s' "$OUT" | grep -c .)"
run "$D"
printed_n="$(printf '%s' "$OUT" | grep -cE '^    ')"
claimed_n="$(printf '%s' "$OUT" | sed -n 's/^\([0-9][0-9]*\) finding(s).*/\1/p')"
if [ "$porcelain_n" = "$claimed_n" ] && [ "$printed_n" = "$claimed_n" ]; then
  ok "every finding counted is also printed ($claimed_n)"
else
  bad "every finding counted is also printed" \
      "porcelain=$porcelain_n printed=$printed_n claimed=${claimed_n:-none}"
fi
if [ "${claimed_n:-0}" -ge 4 ]; then ok "and the fixture really does span several sections"
else bad "and the fixture really does span several sections" "only ${claimed_n:-0} finding(s) - this case would pass vacuously"; fi

echo "== G. could-not-run is never clean =="
EMPTY="$TMP/empty"; rm -rf "$EMPTY"; mkdir -p "$EMPTY"
run "$EMPTY"
c_rc   "a tree with nothing to examine exits 2, not 0" 2
c_says "and says it looked at nothing"                 'could-not-run|nothing to examine'
run "$TMP/definitely-not-here"
c_rc   "a root that does not exist exits 2" 2
OUT="$(bash "$SURVEY" --root "$TMP" --bogus 2>&1)"; RC=$?
c_rc "an unknown argument exits 2, never 0" 2

echo "== H. one-sided drift, and a hooksPath aimed elsewhere =="
# Both from a cross-model review of the first version, and both are the exact
# class this whole script exists to catch - which is the reason they are worth
# a section rather than a line.

# H1. The two hook directions were behind one `&&`, so either side going
# missing skipped BOTH. Delete .claude/hooks/ while settings.json still names
# those scripts and the survey came back CLEAN, while the harness called a
# hook that did not exist on every matching tool call.
D="$(new_copy onesided)"
rm -rf "$D/.claude/hooks"
cat > "$D/.claude/settings.json" <<'JSON'
{ "hooks": { "PreToolUse": [ { "hooks": [
  { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gone.sh\"" }
] } ] } }
JSON
runp "$D"
c_kind "hooks dir deleted: the wired-but-absent script is still reported" hook-missing 'gone.sh'
c_rc   "and that is a finding, not a clean survey" 1

# The mirror: settings.json missing, scripts present. Those scripts are inert,
# and inert is worth saying even though nothing is broken.
D="$(new_copy onesided2)"
rm -f "$D/.claude/settings.json"
printf '#!/usr/bin/env bash\n' > "$D/.claude/hooks/lonely.sh"
runp "$D"
c_kind "settings.json missing: scripts on disk are reported inert" hook-unwired ".claude/hooks/lonely.sh"

# H2. core.hooksPath NON-EMPTY is not the same as pointing HERE. Aimed at
# another directory, git ignores this project's .githooks entirely - and the
# old check suppressed the finding, then went on to test exec bits on hooks
# git will never run. A clean-looking report over a dormant layer.
D="$(new_copy hookspath)"
mkdir -p "$D/.githooks" "$D/somewhere-else"
printf '#!/usr/bin/env bash\n' > "$D/.githooks/pre-push"
chmod +x "$D/.githooks/pre-push" 2>/dev/null

must git -C "$D" config core.hooksPath .githooks
runp "$D"
c_not  "pointing at .githooks is correct and reports nothing" 'githooks-'

must git -C "$D" config core.hooksPath somewhere-else
runp "$D"
c_kind "pointing somewhere else is reported"        githooks-elsewhere "core.hooksPath=somewhere-else"
run "$D"
c_says "and lands under NOT RUNNING, not a footnote" 'NOT RUNNING'

must git -C "$D" config core.hooksPath no-such-dir
runp "$D"
c_kind "pointing at a directory that does not exist is reported" githooks-elsewhere "core.hooksPath=no-such-dir"

# Equivalent spellings of the same directory must NOT be reported. Without
# this pair the check could be a naive string compare against ".githooks" and
# nothing here would notice.
must git -C "$D" config core.hooksPath ./.githooks
runp "$D"
c_not "a ./ prefixed path is the same directory, not a finding" 'githooks-elsewhere'
must git -C "$D" config core.hooksPath "$D/.githooks"
runp "$D"
c_not "an absolute path to the same directory is not a finding" 'githooks-elsewhere'

# =============================================================================
echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
