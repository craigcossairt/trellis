#!/bin/bash
# One command for a scheduled refresh: re-ingest the corpus, then re-index it.
#
#   bash brain/scripts/refresh.sh
#
# This is the line a schedule runs (cron, launchd, Task Scheduler - see
# brain/README.md). It exists so that line is one command with one honest exit
# code, rather than two commands whose first failure the second one hides.
#
# It refreshes; it does not set up. First-time setup (installing QMD, adding the
# collection) is in brain/README.md, and until that has run this exits 2.
#
# A SCHEDULED JOB FAILS WHERE NOBODY IS LOOKING. So a failed run leaves
# brain/.refresh-failed behind, saying which step failed and when, and the
# session-start hook prints it at the top of the next session. A run that
# succeeds removes it. Without that file a refresh that broke in March reads,
# in June, exactly like one that is working.
#
# Exit: 0 refreshed / 1 a step failed (the marker says which) / 2 not set up.
#
# BRAIN_QMD overrides the QMD wrapper, for the test suite.

set -uo pipefail

BRAIN="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
QMD="${BRAIN_QMD:-$BRAIN/bin/qmd}"
FAILED="$BRAIN/.refresh-failed"

if [ ! -f "$BRAIN/.last-ingest" ]; then
  echo "brain refresh: the brain is not set up yet (no brain/.last-ingest). Follow the Setup steps in brain/README.md once; this script only refreshes an existing one." >&2
  exit 2
fi

fail() { # $1 step, $2 exit code
  local now
  now="$(date '+%Y-%m-%d %H:%M')"
  printf '%s - the %s step failed (exit %s). Run: bash brain/scripts/refresh.sh\n' "$now" "$1" "$2" > "$FAILED"
  printf -- '- %s - refresh - FAILED at the %s step (exit %s)\n' "$now" "$1" "$2" >> "$BRAIN/log.md"
  echo "brain refresh: the $1 step failed (exit $2). The index was left as it was. Marker written to brain/.refresh-failed." >&2
  exit 1
}

rc=0
bash "$BRAIN/scripts/ingest.sh" || rc=$?
[ "$rc" -eq 0 ] || fail ingest "$rc"

rc=0
bash "$QMD" update || rc=$?
[ "$rc" -eq 0 ] || fail index "$rc"

rm -f "$FAILED"
printf -- '- %s - refresh - ok\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BRAIN/log.md"
echo "brain refresh: done."
