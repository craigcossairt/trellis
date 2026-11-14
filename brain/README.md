# Project Brain

An optional local knowledge base: BM25 keyword search over your project corpus (docs, commit
history, agent memory), auto-injected into every Claude Code prompt via a UserPromptSubmit hook.

Based on the "Second Brain" pattern: a `raw/` corpus of copied source material, indexed with
[QMD](https://www.npmjs.com/package/@tobilu/qmd), searched at prompt time in ~1-2 seconds.

**Off by default.** The hook exits silently until you initialize (it checks for `.last-ingest`).
`SETUP.md` step 7 has the test for whether to turn it on today: roughly 15 documents of your
own, a few weeks of commit history, material you are bringing with you, or a plan to write
things down as you build. If this project will never need a knowledge base, delete this
directory together with `bin/tests/test-brain-refresh.sh` - nothing else depends on it.

## Setup

1. **Install QMD** (requires [bun](https://bun.sh)):

   ```bash
   bun install -g @tobilu/qmd
   ```

2. **Configure sources** in `config.sh` - which directories/files get copied into the corpus.
   The defaults (docs/ + AGENTS.md + git log) are a sensible start.

3. **Ingest + index:**

   ```bash
   bash brain/scripts/ingest.sh
   bash brain/bin/qmd collection add brain/raw --name project   # first time only
   bash brain/bin/qmd update
   ```

4. **Done.** The hook in `.claude/settings.json` is already wired; the next prompt in a Claude
   Code session will get a `<project-brain-context>` block when the corpus has relevant hits.

Then schedule the refresh below. An index nobody refreshes goes on answering from the day it
was built.

## Keeping it current

The index only knows what the last ingest copied in. One command re-ingests and re-indexes, and
exits non-zero if either step fails:

```bash
bash brain/scripts/refresh.sh
```

Run it once by hand, then have your computer run it once a day.

**It has to run on your own computer.** The corpus and the index are local and are not in git,
so a scheduled job in the cloud (a hosted agent, a CI workflow) has nothing to refresh.

Each of these creates a scheduled job on your computer, so an AI asks you before running
one. Start in the project folder, in the terminal where the by-hand run just worked.

### macOS and Linux (cron)

```bash
bash brain/scripts/install-cron.sh
```

That adds one line to your crontab: the refresh, daily at 9:00. What it does, in order:

1. Builds the job line with your terminal's `PATH` in it. A scheduler starts a job with a
   much shorter `PATH` than your terminal has. The refresh then works by hand and fails on
   the schedule with "command not found", which is the most confusing way for it to fail.
2. Runs the job once the way cron will, with nothing inherited from your terminal. If that
   does not exit 0, it stops and nothing is installed.
3. Reads your crontab. If it cannot be read, it stops and nothing is written.
4. Writes the crontab back with this folder's line added, or replaced if one was there.
   Every other line is kept as it was, byte for byte. Empty lines at the very end of the
   table are the one thing dropped.
5. Reads it back, and reports success only if that read works and what comes back is the
   table it wrote.

It says which step stopped it and why. Run it again after installing bun or node somewhere
new, so the job carries the new `PATH`. To remove the job, run `crontab -e` and delete the
line that names this folder. Cron does not catch up: a computer that is asleep or off at 9:00
skips that day.

Which line counts as this folder's: one the script wrote, meaning a schedule followed by
exactly its job. If you change the time with `crontab -e` the line is still recognised, and
the next run of the script puts it back to 9:00 and says it replaced a line. A line of your
own that runs the refresh some other way, or only mentions it, is not touched. Nor is a
line that starts with `#`, so a copy of the job you commented out stays as a comment. A
line that sets a variable (`NAME = value`) is never taken for the job either, whatever
its value is.

Installing a crontab replaces the whole table, which is why this is a script with tests and
not a few lines to paste. Two earlier versions of this page were lines to paste, and review
found a way for each to empty a crontab. Review of the script's own first version found two
more ways to lose a line, both fixed: it took any line that mentioned this folder's refresh
for its own, and it picked lines out with `grep`, which drops a line that is not valid UTF-8.

What was run, on 2026-11-13: with cron's usual `PATH` the QMD launcher stopped with exit 127
("node: not found"), and with the terminal's `PATH` carried in it ran. The script's steps are
tested against a stand-in for `crontab` (`bin/tests/test-brain-refresh.sh`), on Linux and
under Git Bash. No real crontab was changed, and none of this was run on macOS. Its limits,
each of which it reports instead of guessing:

- It tells "no crontab yet" from a failure by the words `no crontab` in cron's own message.
  A cron that says it another way stops with nothing changed.
- A single quote, a `%` or a line break in `PATH` or in the folder's path cannot be
  written into a cron line safely, so it refuses.
- Some versions of cron are said to cut a command off near 1000 characters. That was not
  checked here. Past 900 it installs the line and says so, with what to do if the scheduled
  run fails.
- On macOS, cron is said to be refused the Documents, Desktop and Downloads folders unless
  it has been given Full Disk Access (System Settings, Privacy & Security). That was not
  checked here either. The trial run cannot show it, because it runs from your terminal,
  which has its own permission. If the project is in one of those folders and nothing new
  appears in `brain/log.md` after 9:00, that is the first thing to look at.
- On Debian and Ubuntu, `crontab -l` leaves out the three-line header cron keeps at the
  top of the table, unless `CRONTAB_NOHEADER=N` is set. With that set the script exits 2
  after a good write, because the table it reads back has the header in it, and each run
  adds those three lines to the table as comments. Unset it for the run. This is from
  reading cron's source (Debian's, Apple's, FreeBSD's and cronie's), not from a run.

### Windows (Task Scheduler)

In PowerShell:

```powershell
$here = (Get-Location).Path
$name = "Brain refresh - $(Split-Path -Leaf $here)"
# Two projects in folders of the same name would get the same task name, and registering
# the second would replace the first. So look at what is there before replacing anything,
# and stop if the look itself fails: not knowing is not the same as nothing being there.
# (Every task is listed and compared by exact name. -TaskName would read [ ] and * in a
# folder name as a pattern, and -TaskPath fails on a folder that holds no task yet.)
$looked = $true
try {
  $old = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -eq $name })
} catch {
  $looked = $false
  "Could not list the scheduled tasks: $($_.Exception.Message)"
}
if (-not $looked) {
  "Nothing was changed."
} elseif ($old.Count -gt 0 -and @($old[0].Actions)[0].WorkingDirectory -ne $here) {
  "A task named '$name' already runs in another folder: $(@($old[0].Actions)[0].WorkingDirectory)"
  "Nothing was changed. Put another name on the second line and run all of these again."
} else {
  $action  = New-ScheduledTaskAction -Execute 'C:\Program Files\Git\bin\bash.exe' `
               -Argument 'brain/scripts/refresh.sh' -WorkingDirectory $here
  $trigger = New-ScheduledTaskTrigger -Daily -At 9am
  # Without these settings a laptop on battery, or one that was asleep at 9:00, skips the day.
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries
  # -Force replaces this folder's own task, so these lines can be run again.
  Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force

  # Run it once through the scheduler, give it a minute, then read the result back.
  Start-ScheduledTask -TaskName $name
  Get-ScheduledTaskInfo -TaskName $name | Select-Object LastRunTime, LastTaskResult
}
```

`LastTaskResult` is `0` after a run that worked, and `brain/log.md` then ends with a new
`refresh - ok` line. `267009` means it is still running and `267011` that it has not run yet,
so read it again in a minute. To remove the task:
`Unregister-ScheduledTask -TaskName $name -Confirm:$false`.

Not run here: no task was registered or started. What was checked on Windows PowerShell
5.1: the commands and their parameters, by building the action, the trigger and the settings;
the look-up of an existing task, which only reads, against the real scheduler; and which way
the lines go, by running them with stand-ins for the four commands that touch the scheduler
(no task of that name, one for this folder, one for another folder, and a look-up that
fails). So the run you start above is the test. Registered this way, the task belongs to your account and runs while
you are signed in.

By hand in the Task Scheduler app, the same task is a daily one whose action starts
`"C:\Program Files\Git\bin\bash.exe"` (keep the quotes), with the argument
`brain/scripts/refresh.sh` and "Start in" set to your project folder, typed without quotes.

### Or ask your AI

"Schedule the brain refresh the way `brain/README.md` says." It runs the script or the
lines above for your system, shows you the entry it made, and tells you what the run reported. A
scheduler built into your coding tool works too, as long as it runs on this computer and you
check its first run the same way.

**A scheduled job fails where nobody is looking, so this one leaves a note.**

- A run that fails writes `brain/.refresh-failed`, naming the step that failed, and the
  session-start hook prints it at the top of your next session. Fix the cause and run the
  command by hand; a clean run removes the note. When the failure was a program that could
  not be found (exit 127), the note says so: run the schedule steps above again, so the job
  carries your current `PATH`.
- A schedule that never starts cannot write that note. That case is caught by age instead:
  once the last ingest is 7 days old, session start says the brain is stale. Change the number
  with `PROJECT_BRAIN_STALE_DAYS`; `0` turns the line off.
- Both lines come from the session-start hook, so they appear only in a tool that runs it
  (`docs/harness-support.md` has the table). In the others, `brain/log.md` is the place to
  look.
- Every run adds a line to `brain/log.md`, which is where to look for when it last worked.

## Layout

```
brain/
├── config.sh        # what gets ingested (edit this)
├── scripts/ingest.sh # copies sources into raw/, secret-scans, stamps .last-ingest
├── scripts/refresh.sh # ingest + index in one command; the line a schedule runs
├── hooks/context-enrichment.sh  # the UserPromptSubmit hook (BM25 top-3 injection)
├── bin/qmd          # QMD wrapper (handles a Windows shebang issue; fine on Mac/Linux)
├── raw/             # the corpus (gitignored - regenerate via ingest)
├── summaries/       # optional hand- or agent-written distillations; ingest picks them up if
│                    # you add them to config.sh
└── log.md           # append-only event log (gitignored)
```

## Notes

- **Kill switch:** `PROJECT_BRAIN_DISABLE=1` bypasses the hook for a session.
  `PROJECT_BRAIN_DEBUG=1` logs to `brain/hooks/debug.log`.
- **Secrets:** the ingest refuses to complete if anything shaped like a real key (GitHub token,
  JWT, PEM, Slack token) lands in `raw/`. Keep it that way - the corpus gets injected into
  prompts.
- **BM25 only in the hook.** Vector search (`qmd vsearch`) works but loads a model (~15s cold) -
  use it manually for deep research, never in the hook path.
- **Keep the corpus out of cloud-synced folders** (iCloud/OneDrive placeholder eviction can
  deadlock indexing). A normal git checkout location is fine.

## Growing it

Ideas that earned their keep in the setup this was extracted from, in rough order of value:

1. **Summaries** - 2-3 distilled context files (strategic / product / technical) regenerated
   monthly by an agent, added to the corpus. Highest signal-per-token in search results.
2. **A scheduled refresh** - now shipped: see Keeping it current above.
3. **A lint pass** - an agent skill that checks the brain for contradictions, stale claims, and
   broken cross-references before each monthly summary refresh.
4. **External sources** - issue-tracker exports and knowledge-base pages copied into `raw/` by an
   agent with the relevant MCP access (they can't be fetched by a plain shell script).
5. **A skill registry** - once you accumulate 15+ skills across sources, a generated catalog
   (name, provenance, trigger phrases, usage counts) plus a weekly pass that drafts new skills
   from recurring multi-step procedures in session transcripts. Only worth it at real scale.
