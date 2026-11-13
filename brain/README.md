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

The lines below can be pasted as they are, by you or by your AI. They create a scheduled job
on your computer, so an AI asks you before running them. Start in the project folder, in the
terminal where the by-hand run just worked.

### macOS and Linux (cron)

A scheduler starts a job with a much shorter `PATH` than your terminal has. The refresh then
works by hand and fails on the schedule with "command not found", which is the most confusing
way for it to fail. So the job carries your terminal's `PATH` with it:

```bash
job="export PATH='$PATH'; cd '$PWD' && bash brain/scripts/refresh.sh >/dev/null 2>&1"

# 1. Run the job the way the scheduler will: with nothing inherited from this terminal.
env -i HOME="$HOME" /bin/sh -c "$job"; ran=$?
echo "exit $ran (the job line is ${#job} characters long)"

# 2. Install it, daily at 9:00, but only if step 1 exited 0. An earlier line for this folder
#    is replaced. Every other line in your crontab is kept. Installing replaces the whole
#    crontab, so it is read first, and if it cannot be read nothing is written: the jobs
#    already in it would be lost.
if [ "$ran" -ne 0 ]; then
  echo "Step 1 did not exit 0, so nothing was installed. Fix that first."
elif old="$(crontab -l 2>/dev/null)" || crontab -l 2>&1 | grep -q 'no crontab'; then
  { [ -z "$old" ] || printf '%s\n' "$old" | grep -vF "cd '$PWD' && bash brain/scripts/refresh.sh"
    printf '%s\n' "0 9 * * * $job"; } | crontab -
else
  echo "Could not read your crontab, so nothing was changed. Run 'crontab -l' to see why."
fi

# 3. Read it back.
crontab -l
```

Step 1 is the check that counts. `exit 0`, and a new `refresh - ok` line at the end of
`brain/log.md`, mean the scheduled run will find its programs. On anything else step 2
installs nothing: fix that, then run the three steps again. If you later install bun or node
somewhere else, run them again too, so the job carries the new `PATH`. To remove the job, run
`crontab -e` and delete its line. Cron does not catch up: a computer that is asleep or off at
9:00 skips that day.

What was run, on 2026-11-13: with cron's usual `PATH` the QMD launcher stopped with exit 127
("node: not found"), and with the terminal's `PATH` carried in as above it ran. Step 2 was run
against a stand-in for `crontab`: it kept the other lines, left one line for the folder
however often it ran, and wrote nothing when step 1 had failed or the stand-in could not be
read. (An earlier version of this step installed over a crontab it could not read, and the
other jobs were gone.) No real crontab was changed, and none of this was run on macOS. Four
limits. Step 2 tells "no crontab yet" from a failure by the words `no crontab` in cron's own
message, so a cron that says it another way stops with nothing changed. Cron reads `%` as a
line break, so a folder or `PATH` entry with a `%` in it needs it written `\%`. A single quote
in either breaks the quoting. And some versions of cron are said to cut a command off near
1000 characters, which was not checked here: step 1 prints how long the line is, and a long
`PATH` can be cut down to the folders that hold `bun` or `node`.

### Windows (Task Scheduler)

In PowerShell:

```powershell
$name    = "Brain refresh - $(Split-Path -Leaf (Get-Location))"
$action  = New-ScheduledTaskAction -Execute 'C:\Program Files\Git\bin\bash.exe' `
             -Argument 'brain/scripts/refresh.sh' -WorkingDirectory (Get-Location).Path
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
# Without these settings a laptop on battery, or one that was asleep at 9:00, skips the day.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
              -DontStopIfGoingOnBatteries
# -Force replaces a task of the same name, so these lines can be run again.
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force

# Run it once through the scheduler, give it a minute, then read the result back.
Start-ScheduledTask -TaskName $name
Get-ScheduledTaskInfo -TaskName $name | Select-Object LastRunTime, LastTaskResult
```

`LastTaskResult` is `0` after a run that worked, and `brain/log.md` then ends with a new
`refresh - ok` line. `267009` means it is still running and `267011` that it has not run yet,
so read it again in a minute. To remove the task:
`Unregister-ScheduledTask -TaskName $name -Confirm:$false`.

Not run here: the commands and their parameters were checked on Windows PowerShell 5.1 by
building the action, the trigger and the settings, and no task was registered or started. So the run you
start above is the test. Registered this way, the task belongs to your account and runs while
you are signed in.

By hand in the Task Scheduler app, the same task is a daily one whose action starts
`"C:\Program Files\Git\bin\bash.exe"` (keep the quotes), with the argument
`brain/scripts/refresh.sh` and "Start in" set to your project folder, typed without quotes.

### Or ask your AI

"Schedule the brain refresh the way `brain/README.md` says." It runs the lines above for your
system, shows you the entry it made, and tells you what the first scheduled run reported. A
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
