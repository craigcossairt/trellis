#!/usr/bin/env bash
# =============================================================================
# test-brain-refresh.sh - behavioral tests for brain/scripts/refresh.sh
# =============================================================================
# refresh.sh is the line a schedule runs, so every way it can fail happens
# where nobody is watching. What is pinned:
#
#   1. It never sets the brain up by accident: with no .last-ingest it exits 2
#      and indexes nothing.
#   2. A failed ingest stops the run. The indexer is NOT called on a corpus the
#      ingest refused (the ingest refuses when it finds a key-shaped string).
#   3. A failed index is a failure, not a success with a warning.
#   4. Either failure leaves brain/.refresh-failed naming the step, and a later
#      success removes it. That marker is the only thing that makes a broken
#      schedule visible (the session-start hook prints it).
#   5. It finds its own brain/ when run by a relative path with CDPATH set.
#
# Hermetic: a temp copy of brain/, a fake QMD named through BRAIN_QMD, no
# network. The key-shaped string in case 2 is built at run time, so this file
# holds nothing a secret scanner would stop on.
#
# Run:  bash bin/tests/test-brain-refresh.sh
# =============================================================================
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
for f in brain/scripts/refresh.sh brain/scripts/ingest.sh brain/config.sh; do
  [ -f "$ROOT/$f" ] || { echo "missing $ROOT/$f" >&2; exit 1; }
done

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "$(printf '%s' "$2" | tail -4 | tr '\n' '|')"; }
must() { "$@" >/dev/null 2>&1 || { echo "FIXTURE FAILED: $*" >&2; exit 1; }; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t brainrefresh)"
trap 'rm -rf "$TMP"' EXIT

# The fake indexer: records its arguments, exits with $QMD_RC (default 0).
cat > "$TMP/fake-qmd" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QMD_CALLS"
exit "${QMD_RC:-0}"
FAKE

N=0; P=""
project() { # a fresh project with a copy of brain/ and one doc; $1 = "setup" to mark it initialised
  N=$((N + 1)); P="$TMP/p$N"
  must mkdir -p "$P/brain/scripts" "$P/brain/raw" "$P/docs"
  must cp "$ROOT/brain/scripts/refresh.sh" "$ROOT/brain/scripts/ingest.sh" "$P/brain/scripts/"
  must cp "$ROOT/brain/config.sh" "$P/brain/config.sh"
  echo "# a decision" > "$P/docs/decision.md"
  echo "# agents" > "$P/AGENTS.md"
  echo "# readme" > "$P/README.md"
  : > "$P/calls"
  if [ "${1:-}" = setup ]; then echo "2020-01-01T00:00:00Z" > "$P/brain/.last-ingest"; fi
  return 0
}

OUT=""; RC=0
run() { # $1 QMD exit code
  RC=0
  OUT=$(QMD_CALLS="$P/calls" QMD_RC="${1:-0}" BRAIN_QMD="$TMP/fake-qmd" bash "$P/brain/scripts/refresh.sh" 2>&1) || RC=$?
}
calls() { wc -l < "$P/calls" | tr -d ' '; }

echo "== not set up"
project; run 0
if [ "$RC" = 2 ]; then ok "no .last-ingest -> exit 2"; else bad "no .last-ingest -> exit 2" "rc=$RC :: $OUT"; fi
if [ "$(calls)" = 0 ]; then ok "nothing was indexed"; else bad "nothing was indexed" "$(cat "$P/calls")"; fi
if [ ! -f "$P/brain/.last-ingest" ]; then ok "it did not stamp an ingest"; else bad "it did not stamp an ingest" "stamp exists"; fi
case "$OUT" in *brain/README.md*) ok "the message points at the README" ;; *) bad "the message points at the README" "$OUT" ;; esac

echo "== a clean refresh"
project setup; run 0
if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit 0" "rc=$RC :: $OUT"; fi
if [ "$(cat "$P/calls")" = update ]; then ok "the indexer was called once, with 'update'"; else bad "the indexer was called once, with 'update'" "$(cat "$P/calls")"; fi
if [ -f "$P/brain/raw/docs/decision.md" ]; then ok "the corpus was re-ingested"; else bad "the corpus was re-ingested" "$(ls -R "$P/brain/raw" 2>&1)"; fi
if [ "$(cat "$P/brain/.last-ingest")" != "2020-01-01T00:00:00Z" ]; then ok "the ingest stamp moved"; else bad "the ingest stamp moved" "still 2020"; fi
if [ ! -f "$P/brain/.refresh-failed" ]; then ok "no failure marker"; else bad "no failure marker" "$(cat "$P/brain/.refresh-failed")"; fi
if grep -q 'refresh - ok' "$P/brain/log.md" 2>/dev/null; then ok "the log has an ok line"; else bad "the log has an ok line" "$(cat "$P/brain/log.md" 2>&1)"; fi

echo "== the index step fails"
project setup; run 3
if [ "$RC" = 1 ]; then ok "exit 1"; else bad "exit 1" "rc=$RC :: $OUT"; fi
if grep -q 'index step failed' "$P/brain/.refresh-failed" 2>/dev/null; then ok "the marker names the index step"; else bad "the marker names the index step" "$(cat "$P/brain/.refresh-failed" 2>&1)"; fi
if grep -q 'FAILED at the index step' "$P/brain/log.md" 2>/dev/null; then ok "the log records the failure"; else bad "the log records the failure" "$(cat "$P/brain/log.md" 2>&1)"; fi
run 0
if [ "$RC" = 0 ] && [ ! -f "$P/brain/.refresh-failed" ]; then ok "the next clean run removes the marker"; else bad "the next clean run removes the marker" "rc=$RC"; fi

echo "== a program that is not found (exit 127)"
# 127 is the shell's "command not found". On a schedule that is nearly always
# PATH, which a scheduler starts short, and the same command then works when
# run by hand. The marker is all the next session sees, so it has to say so.
project setup; run 127
if grep -q 'usually PATH' "$P/brain/.refresh-failed" 2>/dev/null; then ok "exit 127: the marker says a program was not found and names PATH"
else bad "exit 127: the marker says a program was not found and names PATH" "$(cat "$P/brain/.refresh-failed" 2>&1)"; fi
MARK="$(head -n 1 "$P/brain/.refresh-failed" 2>/dev/null)"
if [ -n "$MARK" ] && [ "${#MARK}" -le 200 ]; then ok "exit 127: the marker fits the 200 characters the session-start hook prints"
else bad "exit 127: the marker fits the 200 characters the session-start hook prints" "length ${#MARK}"; fi
case "$MARK" in *'Run: bash brain/scripts/refresh.sh') ok "exit 127: the marker still ends with the command to run" ;; *) bad "exit 127: the marker still ends with the command to run" "$MARK" ;; esac
project setup; run 3
if grep -q 'PATH' "$P/brain/.refresh-failed" 2>/dev/null; then bad "any other exit: the marker does not blame PATH" "$(cat "$P/brain/.refresh-failed")"
else ok "any other exit: the marker does not blame PATH"; fi

echo "== the ingest step fails"
project setup
# A GitHub-token-shaped string, assembled here so it never appears in this file.
printf 'token: %s%s\n' 'ghp' "_$(printf 'A%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36)" > "$P/docs/leaked.md"
run 0
if [ "$RC" = 1 ]; then ok "exit 1"; else bad "exit 1" "rc=$RC :: $OUT"; fi
if [ "$(calls)" = 0 ]; then ok "the indexer was NOT called on a refused corpus"; else bad "the indexer was NOT called on a refused corpus" "$(cat "$P/calls")"; fi
if grep -q 'ingest step failed' "$P/brain/.refresh-failed" 2>/dev/null; then ok "the marker names the ingest step"; else bad "the marker names the ingest step" "$(cat "$P/brain/.refresh-failed" 2>&1)"; fi

echo "== run by a relative path with CDPATH set"
project setup
RC=0
OUT=$(cd "$P" && CDPATH=. QMD_CALLS="$P/calls" BRAIN_QMD="$TMP/fake-qmd" bash brain/scripts/refresh.sh 2>&1) || RC=$?
if [ "$RC" = 0 ] && [ "$(cat "$P/calls")" = update ] && [ -f "$P/brain/raw/docs/decision.md" ]; then
  ok "it still finds its own brain/"
else bad "it still finds its own brain/" "rc=$RC :: $OUT"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
