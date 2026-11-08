#!/usr/bin/env bash
# =============================================================================
# test-check-instruction-budgets.sh - guards the AGENTS.md byte budgets
# =============================================================================
# Guards bin/check-instruction-budgets.sh. The thing under test is not "can it
# add up file sizes". It is "can it ever say UNDER BUDGET about a file it never
# measured". Codex truncates AGENTS.md at its byte limit without a word, so a
# check that goes quiet when its input vanishes is worse than none. A third of this suite is therefore cases that must exit 2, and the
# optional-file cases must say NOT CHECKED rather than ok.
#
# Every case runs against a synthetic fixture tree with its own budgets file,
# never the live AGENTS.md, so the expected numbers do not move as the rule
# files grow. Two cases at the end pin the SHIPPED budgets file and the
# hooks-ci wiring, because a suite that passes while CI never calls the script
# is decoration.
#
# Usage: bash bin/tests/test-check-instruction-budgets.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$HERE/../check-instruction-budgets.sh"
SHIPPED="$HERE/../instruction-budgets.txt"
HOOKS="$HERE/../../.github/workflows/hooks-ci.yml"

PASS=0
FAIL=0
SKIP=0
FAILED_CASES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() {
  FAIL=$((FAIL + 1)); FAILED_CASES+=("$1")
  printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
}
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { # name haystack needle
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "output containing '$3'" "$2" ;; esac
}
lacks() { # name haystack needle
  case "$2" in *"$3"*) bad "$1" "output without '$3'" "$2" ;; *) ok "$1" ;; esac
}

[ -f "$SCRIPT" ] || { echo "cannot find check-instruction-budgets.sh at $SCRIPT" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'chmod -R u+r "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# A file of exactly $2 bytes.
bytes() { # path n
  mkdir -p "$(dirname "$1")"
  head -c "$2" /dev/zero | tr '\0' 'a' > "$1"
}

# A tree with a root AGENTS.md (A bytes), a nested sub/AGENTS.md (B bytes, the
# file Codex appends when started inside sub/), and a budgets file whose body
# is the rest of the arguments, one line each.
tree() { # dir a_bytes b_bytes config-lines...
  local dir="$1" a="$2" b="$3"; shift 3
  mkdir -p "$dir/bin"
  bytes "$dir/AGENTS.md" "$a"
  bytes "$dir/sub/AGENTS.md" "$b"
  printf '%s\n' "$@" > "$dir/bin/instruction-budgets.txt"
}

# The standard config: limit 1000, share 50 -> a cap of 500 per concatenation.
STD=(
  "# test config"
  "limit 1000"
  "share 50"
  "file root AGENTS.md 300"
  "file repo sub/AGENTS.md 300"
  "sum root repo"
)

run_code() { (cd "$1" && shift && bash "$SCRIPT" "$@" >/dev/null 2>&1); echo "$?"; }
run_out()  { (cd "$1" && shift && bash "$SCRIPT" "$@" 2>&1); }

# ---------------------------------------------------------------------------
echo "verdicts"

T="$TMP/under"; tree "$T" 100 100 "${STD[@]}"
eq "everything under budget exits 0" "0" "$(run_code "$T")"
OUT="$(run_out "$T")"
has "the under-budget run names the nested file" "$OUT" "sub/AGENTS.md"
has "the under-budget run prints a result line" "$OUT" "result: ok"

T="$TMP/file_over"; tree "$T" 301 100 "${STD[@]}"
eq "one file over its own budget exits 1" "1" "$(run_code "$T")"
has "the over file is marked OVER" "$(run_out "$T")" "OVER"

T="$TMP/file_at"; tree "$T" 300 100 "${STD[@]}"
eq "a file exactly at its budget is under (> not >=)" "0" "$(run_code "$T")"

# Each file under its own budget, the pair over the share cap. This is the
# case the ticket exists for: no single file looks big.
T="$TMP/sum_over"; tree "$T" 280 280 "${STD[@]}"
eq "a concatenation over the share cap exits 1" "1" "$(run_code "$T")"
SUMLINE="$(run_out "$T" | grep 'root + repo$')"
case "$SUMLINE" in
  OVER*) ok "the concatenation line itself is marked OVER" ;;
  *) bad "the concatenation line itself is marked OVER" "OVER ... root + repo" "$SUMLINE" ;;
esac

# Codex joins the files with a blank line. 249 + 249 + 2 = 500 = the cap.
T="$TMP/sum_at"; tree "$T" 249 249 "${STD[@]}"
eq "a concatenation exactly at the cap is under" "0" "$(run_code "$T")"

# 249 + 250 = 499 is under the cap only if the separator is forgotten.
T="$TMP/sum_sep"; tree "$T" 249 250 "${STD[@]}"
eq "the blank-line separator counts toward the cap" "1" "$(run_code "$T")"

# A Windows checkout (core.autocrlf=true) gives the budgets file CRLF ends.
T="$TMP/crlf"; tree "$T" 280 280 "${STD[@]}"
printf '%s\r\n' "${STD[@]}" > "$T/bin/instruction-budgets.txt"
eq "a CRLF budgets file parses and still finds the pair over" "1" "$(run_code "$T")"

# ---------------------------------------------------------------------------
echo "optional files: NOT CHECKED is not ok"

OPT=("${STD[@]}" "optional web ../web/AGENTS.md 300" "sum root web")

T="$TMP/opt_missing"; tree "$T" 100 100 "${OPT[@]}"
eq "a missing optional file does not fail the run" "0" "$(run_code "$T")"
OUT="$(run_out "$T")"
has "a missing optional file is reported NOT CHECKED" "$OUT" "NOT CHECKED"
has "its concatenation is reported NOT CHECKED too" "$OUT" "NOT CHECKED  root + web"
# Read the line itself: a fixed needle with the wrong column spacing never
# matches anything, which is how the first draft of this case passed under
# the "read a missing optional file as 0 bytes" mutation.
WEBLINE="$(printf '%s\n' "$OUT" | grep 'root + web')"
case "$WEBLINE" in
  ok*) bad "a missing optional file's sum is never printed as ok" "a NOT CHECKED line" "$WEBLINE" ;;
  "") bad "a missing optional file's sum is never printed as ok" "a NOT CHECKED line" "(no line)" ;;
  *) ok "a missing optional file's sum is never printed as ok" ;;
esac

# The web file's own budget (1000) clears its 450 bytes, so the only thing
# over budget here is the root + web sum: skip the sum and this case goes red.
T="$TMP/opt_present"; tree "$T" 100 100 "${STD[@]}" "optional web ../web/AGENTS.md 1000" "sum root web"
bytes "$TMP/web/AGENTS.md" 450
eq "a present optional file is measured (pair 100+450+2 > 500)" "1" "$(run_code "$T")"
rm -rf "$TMP/web"

# ---------------------------------------------------------------------------
echo "could not run: exit 2, never a verdict"

T="$TMP/req_missing"; tree "$T" 100 100 "${STD[@]}"; rm "$T/sub/AGENTS.md"
eq "a missing required file exits 2" "2" "$(run_code "$T")"
lacks "a missing required file prints no ok result" "$(run_out "$T")" "result: ok"

T="$TMP/no_config"; tree "$T" 100 100 "${STD[@]}"; rm "$T/bin/instruction-budgets.txt"
eq "a missing budgets file exits 2" "2" "$(run_code "$T")"

T="$TMP/bad_kw"; tree "$T" 100 100 "${STD[@]}" "fil repo AGENTS.md 300"
eq "an unknown keyword exits 2" "2" "$(run_code "$T")"

T="$TMP/bad_budget"; tree "$T" 100 100 "limit 1000" "share 50" "file root AGENTS.md 30k"
eq "a non-integer budget exits 2" "2" "$(run_code "$T")"

T="$TMP/bad_sum"; tree "$T" 100 100 "${STD[@]}" "sum root website"
eq "a sum naming an undeclared file exits 2" "2" "$(run_code "$T")"

T="$TMP/no_limit"; tree "$T" 100 100 "share 50" "file root AGENTS.md 300"
eq "a budgets file with no limit exits 2" "2" "$(run_code "$T")"

T="$TMP/share0"; tree "$T" 100 100 "limit 1000" "share 0" "file root AGENTS.md 300"
eq "a share of 0 exits 2" "2" "$(run_code "$T")"

T="$TMP/share101"; tree "$T" 100 100 "limit 1000" "share 101" "file root AGENTS.md 300"
eq "a share over 100 exits 2" "2" "$(run_code "$T")"

T="$TMP/no_files"; tree "$T" 100 100 "limit 1000" "share 50"
eq "a budgets file that budgets nothing exits 2" "2" "$(run_code "$T")"

T="$TMP/dup"; tree "$T" 100 100 "${STD[@]}" "file repo sub/AGENTS.md 400"
eq "a name declared twice exits 2" "2" "$(run_code "$T")"

# A directory passes -e and, on Linux, opens and reads as 0 bytes.
T="$TMP/dirpath"; tree "$T" 100 100 "${STD[@]}"; rm "$T/sub/AGENTS.md"; mkdir "$T/sub/AGENTS.md"
eq "a budgeted path that is a directory exits 2" "2" "$(run_code "$T")"

T="$TMP/badarg"; tree "$T" 100 100 "${STD[@]}"
eq "an unknown argument exits 2" "2" "$(run_code "$T" --frobnicate)"
eq "a malformed --today exits 2" "2" "$(run_code "$T" --today 2026-13)"

if [ "$(id -u)" = "0" ]; then
  SKIP=$((SKIP + 1)); printf '  SKIPPED an unreadable required file exits 2 (running as root: chmod 000 stays readable)\n'
else
  T="$TMP/unreadable"; tree "$T" 100 100 "${STD[@]}"; chmod 000 "$T/sub/AGENTS.md"
  if cat "$T/sub/AGENTS.md" >/dev/null 2>&1; then
    SKIP=$((SKIP + 1)); printf '  SKIPPED an unreadable required file exits 2 (this filesystem ignores chmod 000)\n'
  else
    eq "an unreadable required file exits 2" "2" "$(run_code "$T")"
  fi
  chmod 644 "$T/sub/AGENTS.md"
fi

# ---------------------------------------------------------------------------
echo "review tags: reported, never a failure"

T="$TMP/review"; tree "$T" 100 100 "${STD[@]}"
printf 'Rule one (review 2026-03).\nRule two (review 2026-11).\nRule three (review 2027-01).\n' > "$T/AGENTS.md"
eq "a past review date does not fail the run" "0" "$(run_code "$T" --today 2026-11)"
OUT="$(run_out "$T" --today 2026-11)"
has "a past review date is listed with file and line" "$OUT" "past review 2026-03: AGENTS.md:1"
lacks "the current month is not past" "$OUT" "past review 2026-11"
lacks "a future month is not past" "$OUT" "past review 2027-01"

# ---------------------------------------------------------------------------
echo "the shipped budgets file and its wiring"

if [ -f "$SHIPPED" ]; then
  CFG="$(sed 's/#.*//' "$SHIPPED")"
  has "the shipped limit is Codex's default project_doc_max_bytes" "$CFG" "limit 32768"
  if printf '%s\n' "$CFG" | grep -Eq '^file[[:space:]]+[a-z]+[[:space:]]+AGENTS\.md[[:space:]]'; then
    ok "the shipped file budgets the root AGENTS.md"
  else
    bad "the shipped file budgets the root AGENTS.md" "a 'file <name> AGENTS.md <bytes>' line" "$CFG"
  fi
else
  bad "the shipped budgets file exists" "$SHIPPED" "missing"
fi

# No `|| true` on the greps below: this script does not run under set -e, and
# the file is proven to exist on the line above, so a non-match is the only
# way grep can return 1 here.
if [ -f "$HOOKS" ]; then
  # The live step must call the script on the real tree, not only this suite,
  # and must not swallow its exit code.
  LIVE="$(grep -n 'bash bin/check-instruction-budgets.sh' "$HOOKS")"
  if [ -n "$LIVE" ]; then ok "hooks-ci runs the check on the live tree"; else bad "hooks-ci runs the check on the live tree" "a step calling bin/check-instruction-budgets.sh" "none"; fi
  # The whole step, not just the calling line: a `|| true` on the next line
  # or continue-on-error on the step would swallow the exit code too.
  STEP="$(awk '/^      - name: Instruction-file byte budgets$/ {on=1; print; next} on && /^      - name:/ {exit} on' "$HOOKS")"
  if [ -n "$STEP" ]; then ok "the live budget step is found by name"; else bad "the live budget step is found by name" "the step block" "none"; fi
  lacks "the live budget step has no || true" "$STEP" "|| true"
  lacks "the live budget step has no continue-on-error" "$STEP" "continue-on-error"
  lacks "the live budget step has no set +e" "$STEP" "set +e"
  # The opt-out (no budgets file -> skip) is for copies only. In the template a
  # missing budgets file must reach the script and exit 2, so the skip has to
  # stay conditioned on the repository name AND on the file being absent.
  if printf '%s\n' "$STEP" | grep -F 'GITHUB_REPOSITORY' | grep -qF '! -e bin/instruction-budgets.txt'; then
    ok "the live step skips only in a copy with no budgets file"
  else
    bad "the live step skips only in a copy with no budgets file" "one condition naming GITHUB_REPOSITORY and the absent budgets file" "$STEP"
  fi
  SUITE="$(grep -c 'bash bin/tests/test-check-instruction-budgets.sh' "$HOOKS")"
  eq "hooks-ci runs this suite on Linux and on Windows" "2" "$SUITE"
else
  bad "hooks-ci.yml exists" "$HOOKS" "missing"
fi

echo
echo "check-instruction-budgets suite: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
  printf '  failed: %s\n' "${FAILED_CASES[@]}"
  exit 1
fi
exit 0
