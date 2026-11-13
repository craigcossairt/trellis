#!/bin/bash
# Put the daily brain refresh in your crontab (macOS and Linux).
#
#   bash brain/scripts/install-cron.sh
#
# Windows has no cron: brain/README.md has the Task Scheduler lines instead.
#
# INSTALLING A CRONTAB REPLACES THE WHOLE TABLE. Every way this can go wrong
# ends with somebody else's jobs gone, so it is a script with a test suite
# (bin/tests/test-brain-refresh.sh) and not a few lines to paste. Two earlier
# versions were lines to paste, and each could empty a crontab: one wrote over
# a table it had failed to read, the other wrote an empty table when the shell
# it was pasted into stopped at the first failed command. The first version of
# this script lost lines too: it took any line that mentioned this folder's
# refresh for its own, and it picked lines out with grep, which drops a line
# that is not valid UTF-8 when the terminal says the text is.
#
# What it does, in order. It stops at the first step that fails, and nothing
# is written before step 4.
#   1. Builds the job line. A scheduler starts a job with a much shorter PATH
#      than a terminal has, and the refresh then fails with "command not
#      found" where nobody is looking. So the line carries the PATH of the
#      terminal this was run from.
#   2. Runs that job once the way cron will, with nothing inherited from this
#      terminal. If it does not exit 0, nothing is installed.
#   3. Reads your crontab. If it cannot be read, nothing is written.
#   4. Writes it back with this folder's line added, or replaced if one was
#      there. Every other line is kept, in order, byte for byte.
#   5. Reads it back. The write counts only if what comes back is the table
#      that was written.
#
# Which line is this folder's: one this script wrote. That is a schedule, then
# exactly the job, with whatever PATH it carried. Change the time in
# `crontab -e` and it is still recognised, and the next run of this script
# puts it back to 9:00. A line of your own that runs the refresh some other
# way is not recognised and is left alone, and so is any line that starts
# with #.
#
# Run it again after installing bun or node somewhere new, so the job carries
# the new PATH. To remove the job: `crontab -e`, and delete the line that
# names this folder. Cron does not catch up: a computer that is asleep or off
# at 9:00 skips that day.
#
# Exit: 0 installed and read back / 1 nothing was installed (it says why) /
#       2 a table was written and reading it back did not show what was
#         written. Look at `crontab -l` yourself.

set -uo pipefail

BRAIN="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
ROOT="$(dirname -- "$BRAIN")"
say() { printf 'install-cron: %s\n' "$1" >&2; }

command -v crontab >/dev/null 2>&1 || {
  say "there is no crontab command here. Nothing was installed. On Windows, use the Task Scheduler lines in brain/README.md."
  exit 1
}

# The job line holds PATH and the project folder inside single quotes, and
# cron reads a percent sign as the end of the command. A line break would
# split the entry in two. None of the three can be written safely, so none is.
NL='
'
for pair in "PATH:$PATH" "the project folder:$ROOT"; do
  what="${pair%%:*}"; value="${pair#*:}"
  case "$value" in
    *"'"*) say "$what has a single quote in it, which would end the quoting in the job line. Nothing was installed."; exit 1 ;;
    *%*)   say "$what has a percent sign in it, which cron reads as the end of the command. Nothing was installed."; exit 1 ;;
    *"$NL"*) say "$what has a line break in it. Nothing was installed."; exit 1 ;;
  esac
done

# MARK names this folder. Another project's refresh line names another folder
# and is left alone.
MARK="cd '$ROOT' && bash brain/scripts/refresh.sh"
JOBHEAD="export PATH='"
JOBTAIL="'; $MARK >/dev/null 2>&1"
JOB="$JOBHEAD$PATH$JOBTAIL"
LINE="0 9 * * * $JOB"

# A crontab line is this folder's only when it is a line this script writes: a
# schedule (five fields, or one @word), then exactly the job, with whatever
# PATH it carried. This folder's name turning up in a line is not enough. A
# job that mentions the command in a message, or runs something before or
# after it, is somebody else's. So is a line that starts with #: a copy of the
# job that somebody commented out is a comment, and stays.
is_mine() { # $1 one crontab line
  local line rest carried
  line="${1#"${1%%[![:space:]]*}"}"
  case "$line" in
    '#'*) return 1 ;;
    @*) read -r _ rest <<< "$line" ;;
    *)  read -r _ _ _ _ _ rest <<< "$line" ;;
  esac
  case "$rest" in "$JOBHEAD"*"$JOBTAIL") ;; *) return 1 ;; esac
  carried="${rest#"$JOBHEAD"}"; carried="${carried%"$JOBTAIL"}"
  case "$carried" in *"'"*) return 1 ;; esac
  return 0
}

# --- 2. the trial run ----------------------------------------------------------
rc=0
env -i HOME="${HOME:-/}" /bin/sh -c "$JOB" || rc=$?
if [ "$rc" -ne 0 ]; then
  say "the job did not run clean in cron's bare environment (exit $rc), so nothing was installed."
  case "$rc" in
    127) say "Exit 127 is 'command not found': a program the refresh needs is not on this terminal's PATH either." ;;
    2)   say "Exit 2 from the refresh means the brain is not set up yet. Follow the Setup steps in brain/README.md first." ;;
    *)   say "Run 'bash brain/scripts/refresh.sh' to see the failure, fix it, then run this again." ;;
  esac
  exit 1
fi

# --- 3. read the crontab, once -------------------------------------------------
# "No crontab yet" and "could not read it" both exit non-zero. Only cron's own
# words tell them apart, and anything that is not plainly the first is treated
# as the second: writing a fresh table over one that could not be read is how
# other people's jobs get lost.
err="$(mktemp 2>/dev/null || mktemp -t installcron)" || { say "could not make a temporary file. Nothing was changed."; exit 1; }
rc=0
old="$(crontab -l 2>"$err")" || rc=$?
if [ "$rc" -ne 0 ]; then
  if grep -qi 'no crontab' "$err"; then
    old=""
  else
    say "could not read your crontab ($(head -n 1 "$err")). Nothing was changed."
    rm -f "$err"
    exit 1
  fi
fi
rm -f "$err"

# --- 4. write it back with this folder's line replaced ---------------------------
# Line by line in the shell, and not through grep or sed: a tool that reads
# the table as text may drop a line it cannot decode, and a line dropped here
# is a job lost.
kept=""; others=0; replaced=0
if [ -n "$old" ]; then
  while IFS= read -r line; do
    if is_mine "$line"; then
      replaced=$((replaced + 1))
    else
      kept="$kept$line$NL"
      if [ -n "$line" ]; then others=$((others + 1)); fi
    fi
  done <<< "$old"
fi
new="$kept$LINE"

rc=0
printf '%s\n' "$new" | crontab - || rc=$?
if [ "$rc" -ne 0 ]; then
  say "crontab refused the new table (exit $rc). Run 'crontab -l' to see what is there now."
  exit 1
fi

# --- 5. read it back -------------------------------------------------------------
# What comes back has to be what was written, whole. Counting lines is not
# enough: a table with the right number of lines can still be another table.
# A read that fails here gives nothing, which is not what was written either.
now="$(crontab -l 2>/dev/null)" || true
if [ "$now" != "$new" ]; then
  say "a new table was written, and what crontab holds now is not that table. Run 'crontab -l' and check it: it should end with this folder's line and hold your $others other line(s) as they were."
  exit 2
fi

echo "Installed: the brain refresh for $ROOT runs daily at 9:00."
if [ "$replaced" -gt 0 ]; then
  echo "Replaced $replaced line(s) this script wrote for this folder before."
fi
echo "Your crontab has $others other line(s), kept as they were."
if [ "${#LINE}" -gt 900 ]; then
  echo "Note: the job line is ${#LINE} characters long. Some versions of cron are said to cut a command off near 1000. That was not checked here. If the scheduled run fails, shorten PATH to the folders that hold bun or node and run this again."
fi
echo "To check it now: tail -n 1 brain/log.md should be a 'refresh - ok' line from a minute ago."
