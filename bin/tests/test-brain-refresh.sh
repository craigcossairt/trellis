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
# And brain/scripts/install-cron.sh, which puts that line in a crontab.
# Installing a crontab replaces the whole table, so the ways it can go wrong
# all end with somebody else's jobs gone:
#
#   6. It writes only after the job ran clean once in cron's own bare
#      environment, with nothing inherited from the terminal, and only after
#      the crontab was read. A crontab that cannot be read is never written
#      over, and a failed read is not retried.
#   7. Every other line survives, in order and byte for byte, however often
#      it is run (empty lines at the very end of the table are the one
#      thing dropped), and this folder's line is there exactly once. A crontab
#      that held only this folder's line ends with that line, not with
#      nothing. A line is this folder's only when it is the line the script
#      writes: one that mentions the refresh, runs something besides it, or
#      sets a variable to it, is somebody else's and stays.
#   8. It believes the write only when the table it reads back is the table
#      it wrote: a crontab that accepts a table and keeps nothing, drops a
#      line, keeps the old table, changes another job, or fails when it is
#      read back, is exit 2, not 0.
#   9. What cannot be written into a cron line safely is refused before
#      anything is run: a single quote, a percent sign or a line break, in
#      PATH or in the project folder's own path.
#
# The crontab here is a stand-in, first on PATH. The section stops before its
# first case if that stand-in is not the `crontab` the shell would run, so a
# real crontab is never read or written by this suite.
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

echo "== install-cron.sh: the schedule goes in without a crontab being lost"
# $CRON/mode: none (no crontab yet), has, fail (it cannot be read), flaky (the
# first read fails and later ones work), writefail (a new table is refused),
# lossy (a new table is accepted and nothing is kept), lastonly (a new table
# is accepted and only its last line is kept), stale (a new table is accepted
# and the old one stays), swap (a new table is accepted with its first line
# changed into another job), sour (a new table is accepted and kept, and
# reading it back prints it and fails).
CRON="$TMP/cron"; export CRON
must mkdir -p "$CRON/bin"
cat > "$CRON/bin/crontab" <<'FAKE'
#!/usr/bin/env bash
mode="$(cat "$CRON/mode")"
case "${1:-}" in
  -l)
    echo x >> "$CRON/reads"
    case "$mode" in
      none)  echo "no crontab for someone" >&2; exit 1 ;;
      fail)  echo "crontab: cannot open your crontab: Permission denied" >&2; exit 1 ;;
      flaky) echo has > "$CRON/mode"; echo "crontab: temporary failure" >&2; exit 1 ;;
      soured) cat "$CRON/store"; echo "crontab: read error" >&2; exit 1 ;;
      *)     cat "$CRON/store"; exit 0 ;;
    esac ;;
  -)
    echo x >> "$CRON/writes"
    case "$mode" in
      writefail) cat > /dev/null; echo "crontab: errors in crontab file" >&2; exit 1 ;;
      lossy)     cat > /dev/null; : > "$CRON/store"; exit 0 ;;
      lastonly)  tail -n 1 > "$CRON/store"; echo has > "$CRON/mode"; exit 0 ;;
      stale)     cat > /dev/null; exit 0 ;;
      swap)      sed '1s|.*|1 1 * * * /bin/something-else|' > "$CRON/store"; exit 0 ;;
      sour)      cat > "$CRON/store"; echo soured > "$CRON/mode"; exit 0 ;;
      *)         cat > "$CRON/store"; echo has > "$CRON/mode"; exit 0 ;;
    esac ;;
esac
exit 64
FAKE
chmod +x "$CRON/bin/crontab"
if [ "$(PATH="$CRON/bin:$PATH" command -v crontab)" != "$CRON/bin/crontab" ]; then
  echo "the stand-in crontab is not the one that would run; stopping before a real crontab is touched" >&2
  exit 1
fi

OTHER='5 4 * * * /usr/local/bin/backup'
cronproject() { # $1 what the project's QMD exits with in the trial run, $2 the stand-in's mode
  project setup
  must mkdir -p "$P/brain/bin"
  # The trial run inherits nothing, so the fake indexer is the project's own
  # wrapper rather than one named through BRAIN_QMD.
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/trial-calls"\nexit %s\n' "$P" "${1:-0}" > "$P/brain/bin/qmd"
  cp "$ROOT/brain/scripts/install-cron.sh" "$P/brain/scripts/" 2>/dev/null
  echo "${2:-none}" > "$CRON/mode"; : > "$CRON/store"; : > "$CRON/writes"; : > "$CRON/reads"
}
install() { RC=0; OUT=$(PATH="$CRON/bin:$PATH" bash "$@" "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?; }
writes() { wc -l < "$CRON/writes" | tr -d ' '; }
reads() { wc -l < "$CRON/reads" | tr -d ' '; }
lines() { grep -c . "$CRON/store"; }
mine() { grep -cF "cd '$P' && bash brain/scripts/refresh.sh" "$CRON/store"; }

cronproject; install
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && [ "$(mine)" = 1 ]; then ok "no crontab yet: exit 0, and the crontab is this one line"
else bad "no crontab yet: exit 0, and the crontab is this one line" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi
case "$(cat "$CRON/store")" in
  "0 9 * * * export PATH='"*"$CRON/bin"*"'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1") ok "the line runs daily at 9:00, carries the caller's PATH, and changes into the project" ;;
  *) bad "the line runs daily at 9:00, carries the caller's PATH, and changes into the project" "$(cat "$CRON/store")" ;;
esac
if [ "$(cat "$P/trial-calls" 2>/dev/null)" = update ]; then ok "the job was run once, for real, before it was installed"
else bad "the job was run once, for real, before it was installed" "$(cat "$P/trial-calls" 2>&1)"; fi

cronproject 0 has; printf '%s\n' "$OTHER" '' '# weekly' '0 1 * * 0 /home/me/weekly.sh' > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(head -n 4 "$CRON/store" | tr '\n' '|')" = "$OTHER||# weekly|0 1 * * 0 /home/me/weekly.sh|" ] && [ "$(mine)" = 1 ]; then
  ok "other jobs are kept as they were, in order, and this one is added"
else bad "other jobs are kept as they were, in order, and this one is added" "rc=$RC :: $(cat "$CRON/store")"; fi
case "$OUT" in
  *"has 3 other line(s)"*) ok "and it says how many other lines were kept, not counting the empty one" ;;
  *) bad "and it says how many other lines were kept, not counting the empty one" "$OUT" ;;
esac
install; install
if [ "$RC" = 0 ] && [ "$(mine)" = 1 ] && [ "$(lines)" = 4 ]; then ok "run twice more: still one line for this folder, and the others untouched"
else bad "run twice more: still one line for this folder, and the others untouched" "rc=$RC mine=$(mine) lines=$(lines)"; fi

# The crontab holds nothing but this folder's old line. Taking that line out
# leaves an empty table, and the new line still has to go in.
cronproject 0 has; install; install
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && [ "$(mine)" = 1 ]; then ok "a crontab that held only this folder's line: replaced, not emptied"
else bad "a crontab that held only this folder's line: replaced, not emptied" "rc=$RC :: $(cat "$CRON/store")"; fi
install -e
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && [ "$(mine)" = 1 ]; then ok "and the same when the shell is told to stop at any failed command (bash -e)"
else bad "and the same when the shell is told to stop at any failed command (bash -e)" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi
cronproject; install -e
if [ "$RC" = 0 ] && [ "$(mine)" = 1 ]; then ok "no crontab yet, under bash -e: installed"
else bad "no crontab yet, under bash -e: installed" "rc=$RC :: $OUT"; fi

cronproject 0 has
printf '%s\n' "0 9 * * * export PATH='/usr/bin'; cd '/other/project' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(grep -c 'brain/scripts/refresh.sh' "$CRON/store")" = 2 ] && [ "$(mine)" = 1 ]; then ok "another project's refresh line is kept"
else bad "another project's refresh line is kept" "rc=$RC :: $(cat "$CRON/store")"; fi

# A line is this folder's only when it is the line this script writes: a
# schedule, then exactly this job. One that mentions the command, or runs
# something besides it, is somebody else's and stays, whole.
stays() { # $1 label, $2 the line
  printf '%s\n' "$OTHER" "$2" > "$CRON/store"; install
  if [ "$RC" = 0 ] && [ "$(lines)" = 3 ] && [ "$(grep -cxF -- "$2" "$CRON/store")" = 1 ]; then ok "$1"
  else bad "$1" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi
}
cronproject 0 has
stays "a job that only mentions this folder's refresh in a message is kept" \
  "* * * * * logger \"cd '$P' && bash brain/scripts/refresh.sh\""
cronproject 0 has
stays "a person's own line for this folder that runs something after the refresh is kept" \
  "30 9 * * 1 cd '$P' && bash brain/scripts/refresh.sh && /home/me/after.sh"
cronproject 0 has
stays "a line that ends like this job and does not start like it is kept" \
  "0 9 * * * true'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"
cronproject 0 has
stays "a line that runs another command between the PATH and the refresh is kept" \
  "0 9 * * * export PATH='/usr/bin'; echo 'x'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"
cronproject 0 has
stays "a line with a sixth word before the job is kept" \
  "0 9 * * * nice export PATH='/usr/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"
cronproject 0 has
stays "a commented-out copy of this folder's line is kept" \
  "#0 9 * * * export PATH='/usr/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"
cronproject 0 has
stays "and so is one with spaces before the #" \
  "  #0 9 * * * export PATH='/usr/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"
# `NAME = value` sets a variable for the jobs below it, and the value may be
# this very job. Five words stand before it there too, and none is a time.
cronproject 0 has
stays "a line that sets a variable to this folder's job is kept" \
  "BRAIN_REFRESH = cd /tmp && export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"
cronproject 0 has
stays "and so is one whose name starts with @" \
  "@x= export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1"

# Its own line is its own whatever time and PATH it carries.
cronproject 0 has
printf '%s\n' "$OTHER" "0 8 * * 1-5 export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(lines)" = 2 ] && [ "$(mine)" = 1 ] && ! grep -q '/old/bin' "$CRON/store"; then ok "this folder's line with another time and an older PATH is replaced, not doubled"
else bad "this folder's line with another time and an older PATH is replaced, not doubled" "rc=$RC :: $(cat "$CRON/store")"; fi
case "$OUT" in
  *"eplaced 1 "*) ok "and it says one line was replaced" ;;
  *) bad "and it says one line was replaced" "$OUT" ;;
esac
cronproject 0 has
printf '%s\n' "@daily export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && ! grep -q '@daily' "$CRON/store"; then ok "and so is one whose schedule was rewritten as @daily"
else bad "and so is one whose schedule was rewritten as @daily" "rc=$RC :: $(cat "$CRON/store")"; fi
cronproject 0 has
printf '%s\n' "*/30 9 * * mon,fri export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && [ "$(mine)" = 1 ] && ! grep -q '/old/bin' "$CRON/store"; then ok "and one with a step, a list and day names in its schedule"
else bad "and one with a step, a list and day names in its schedule" "rc=$RC :: $(cat "$CRON/store")"; fi
cronproject 0 has
printf '%s  \n' "0 8 * * * export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && [ "$(mine)" = 1 ] && ! grep -q '/old/bin' "$CRON/store"; then ok "and one with spaces after it"
else bad "and one with spaces after it" "rc=$RC :: $(cat "$CRON/store")"; fi
cronproject 0 has
printf '  %s\n' "@daily export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(lines)" = 1 ] && [ "$(mine)" = 1 ] && ! grep -q '@daily' "$CRON/store"; then ok "and one with spaces before an @ schedule"
else bad "and one with spaces before an @ schedule" "rc=$RC :: $(cat "$CRON/store")"; fi
cronproject 0 has; echo "$OTHER" > "$CRON/store"; install
case "$RC/$OUT" in
  0/*"eplaced"*) bad "a first install does not say anything was replaced" "$OUT" ;;
  0/*) ok "a first install does not say anything was replaced" ;;
  *) bad "a first install does not say anything was replaced" "rc=$RC :: $OUT" ;;
esac

# Lines are kept byte for byte. grep, told the text is UTF-8, drops a line
# that is not, so nothing here may depend on a filter that reads the text.
# That only shows where a UTF-8 locale is installed and grep goes by it, so
# the case looks for one first, and says so when it runs without one.
UTF8=""
for loc in C.UTF-8 en_US.UTF-8; do
  if [ "$(printf 'caf\351\n' | LC_ALL="$loc" grep -c 'caf.' 2>/dev/null)" = 0 ]; then UTF8="$loc"; break; fi
done
if [ -z "$UTF8" ]; then
  UTF8=C
  echo "  note no UTF-8 locale here in which grep drops such a line. The next case runs in C, where a script that filters with grep would pass it too."
fi
cronproject 0 has
printf '# caf\351 au lait\n0 3 * * * /home/jos\351/bin/nightly.sh\n' > "$CRON/store"
cp "$CRON/store" "$TMP/latin1.want"; RC=0
OUT=$(LC_ALL="$UTF8" PATH="$CRON/bin:$PATH" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
if [ "$RC" = 0 ] && head -n 2 "$CRON/store" | cmp -s - "$TMP/latin1.want" && [ "$(wc -l < "$CRON/store" | tr -d ' ')" = 3 ]; then
  ok "lines that are not valid UTF-8 are kept, byte for byte (locale $UTF8)"
else bad "lines that are not valid UTF-8 are kept, byte for byte (locale $UTF8)" "rc=$RC :: $OUT :: $(od -c "$CRON/store" | head -5)"; fi
# The one thing not kept: empty lines at the very end of the table.
cronproject 0 has; printf '%s\n\n\n' "$OTHER" > "$CRON/store"; install
if [ "$RC" = 0 ] && [ "$(wc -l < "$CRON/store" | tr -d ' ')" = 2 ] && [ "$(head -n 1 "$CRON/store")" = "$OTHER" ] && [ "$(mine)" = 1 ]; then
  ok "empty lines at the very end of the table are dropped, and the job before them is kept"
else bad "empty lines at the very end of the table are dropped, and the job before them is kept" "rc=$RC :: $OUT :: $(od -c "$CRON/store" | head -5)"; fi

cronproject 0 fail; echo "$OTHER" > "$CRON/store"; install
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(cat "$CRON/store")" = "$OTHER" ]; then ok "the crontab cannot be read: exit 1, nothing written"
else bad "the crontab cannot be read: exit 1, nothing written" "rc=$RC writes=$(writes) :: $OUT"; fi
case "$OUT" in
  *"Permission denied"*"othing was changed"*) ok "and it says why, and that nothing was changed" ;;
  *) bad "and it says why, and that nothing was changed" "$OUT" ;;
esac

cronproject 0 flaky; echo "$OTHER" > "$CRON/store"; install
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(reads)" = 1 ]; then ok "a read that fails is not tried again and then written over"
else bad "a read that fails is not tried again and then written over" "rc=$RC writes=$(writes) reads=$(reads) :: $OUT"; fi

cronproject 3 has; echo "$OTHER" > "$CRON/store"; install
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(reads)" = 0 ]; then ok "the trial run fails: exit 1, and the crontab is not touched"
else bad "the trial run fails: exit 1, and the crontab is not touched" "rc=$RC writes=$(writes) reads=$(reads) :: $OUT"; fi
case "$OUT" in
  *"othing was installed"*) ok "and it says nothing was installed" ;;
  *) bad "and it says nothing was installed" "$OUT" ;;
esac

# Cron starts the job with none of this terminal's settings. An indexer that
# works only because of one of them must not get the job installed.
cronproject 3 has; echo "$OTHER" > "$CRON/store"; RC=0
OUT=$(QMD_CALLS="$P/calls" BRAIN_QMD="$TMP/fake-qmd" PATH="$CRON/bin:$PATH" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ]; then ok "the job works only with a setting this terminal has: nothing is installed"
else bad "the job works only with a setting this terminal has: nothing is installed" "rc=$RC writes=$(writes) :: $OUT"; fi

cronproject; rm -f "$P/brain/.last-ingest"; install
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ]; then ok "a brain that is not set up yet: nothing is installed"
else bad "a brain that is not set up yet: nothing is installed" "rc=$RC writes=$(writes) :: $OUT"; fi

cronproject 0 writefail; install
if [ "$RC" = 1 ] && [ "$(mine)" = 0 ]; then ok "the new table is refused: exit 1"
else bad "the new table is refused: exit 1" "rc=$RC :: $OUT"; fi

# The write is believed only after it is read back.
cronproject 0 lossy; install
if [ "$RC" = 2 ]; then ok "the table is accepted and nothing is kept: exit 2, not 0"
else bad "the table is accepted and nothing is kept: exit 2, not 0" "rc=$RC :: $OUT"; fi

cronproject 0 lastonly; echo "$OTHER" > "$CRON/store"; install
if [ "$RC" = 2 ] && [ "$(mine)" = 1 ]; then ok "this folder's line is kept and another line is dropped: exit 2, not 0"
else bad "this folder's line is kept and another line is dropped: exit 2, not 0" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi

# The table read back has to be the table that was written, not one with the
# same number of lines.
cronproject 0 stale
printf '%s\n' "0 8 * * * export PATH='/old/bin'; cd '$P' && bash brain/scripts/refresh.sh >/dev/null 2>&1" > "$CRON/store"; install
if [ "$RC" = 2 ]; then ok "the table is accepted and the old one is still there: exit 2, not 0"
else bad "the table is accepted and the old one is still there: exit 2, not 0" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi
cronproject 0 swap; echo "$OTHER" > "$CRON/store"; install
if [ "$RC" = 2 ] && [ "$(lines)" = 2 ] && [ "$(mine)" = 1 ]; then ok "another job comes back changed, with the line count the same: exit 2, not 0"
else bad "another job comes back changed, with the line count the same: exit 2, not 0" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi
cronproject 0 sour; echo "$OTHER" > "$CRON/store"; install
if [ "$RC" = 2 ] && [ "$(mine)" = 1 ]; then ok "reading the table back prints it and fails: exit 2, not 0"
else bad "reading the table back prints it and fails: exit 2, not 0" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi

# A single quote would end the quoting in the job line, cron reads % as the
# end of the command, and a line break would make two entries of one. None can
# be written safely, so none is. The quotes here are balanced on purpose: the
# job would run, with a PATH that is not the one it was given.
cronproject; RC=0; OUT=$(PATH="$CRON/bin:$PATH:/opt/a'b'c" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(reads)" = 0 ]; then ok "a single quote in PATH: refused before anything is run"
else bad "a single quote in PATH: refused before anything is run" "rc=$RC :: $OUT"; fi
cronproject; RC=0; OUT=$(PATH="$CRON/bin:$PATH:/opt/100%" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(reads)" = 0 ]; then ok "a percent sign in PATH: refused before anything is run"
else bad "a percent sign in PATH: refused before anything is run" "rc=$RC :: $OUT"; fi
cronproject; RC=0; OUT=$(PATH="$CRON/bin:$PATH:/opt/a
b" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(reads)" = 0 ]; then ok "a line break in PATH: refused before anything is run"
else bad "a line break in PATH: refused before anything is run" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi
cronproject; mv "$P" "$TMP/p100%$N"; P="$TMP/p100%$N"; install
if [ "$RC" = 1 ] && [ "$(writes)" = 0 ] && [ "$(reads)" = 0 ] && printf '%s' "$OUT" | grep -q 'project folder'; then ok "a percent sign in the project folder's path: refused, and it says which"
else bad "a percent sign in the project folder's path: refused, and it says which" "rc=$RC :: $OUT"; fi

cronproject; RC=0
OUT=$(PATH="$CRON/bin:$PATH$(printf ':/opt/padding-%s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60)" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
case "$RC/$OUT" in
  0/*"characters"*"not checked"*) ok "a very long job line is installed, with a warning that says what is not known" ;;
  *) bad "a very long job line is installed, with a warning that says what is not known" "rc=$RC :: $OUT" ;;
esac

cronproject; RC=0; OUT=$(PATH="$CRON/bin:/usr/bin:/bin" bash "$P/brain/scripts/install-cron.sh" 2>&1) || RC=$?
case "$RC/$OUT" in
  0/*"Note:"*) bad "a job line of ordinary length gets no warning" "$OUT" ;;
  0/*) ok "a job line of ordinary length gets no warning" ;;
  *) bad "a job line of ordinary length gets no warning" "rc=$RC :: $OUT" ;;
esac

cronproject; RC=0
OUT=$(cd "$P/.." && CDPATH=. PATH="$CRON/bin:$PATH" bash "$(basename "$P")/brain/scripts/install-cron.sh" 2>&1) || RC=$?
if [ "$RC" = 0 ] && [ "$(mine)" = 1 ]; then ok "run by a relative path with CDPATH set: the line names the project's full path"
else bad "run by a relative path with CDPATH set: the line names the project's full path" "rc=$RC :: $OUT :: $(cat "$CRON/store")"; fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
