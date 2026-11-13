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

- **macOS and Linux (cron).** Run `crontab -e` and add one line, with your project's real path:

  ```
  0 9 * * * cd /path/to/your/project && bash brain/scripts/refresh.sh >/dev/null 2>&1
  ```

  cron starts jobs with a very short `PATH`. If the refresh works by hand and fails on the
  schedule, that is the usual reason: add a `PATH=` line above it that includes the folder bun
  was installed into, written out in full (cron does not expand `$HOME` on that line).
- **Windows (Task Scheduler).** Create a basic task that runs daily, with the action "Start a
  program":
  - Program/script: `C:\Program Files\Git\bin\bash.exe`
  - Add arguments: `brain/scripts/refresh.sh`
  - Start in: your project folder, typed without quotes
- **Or ask your AI:** "schedule `bash brain/scripts/refresh.sh` to run daily on this computer".
  A scheduler built into your coding tool works too, as long as it runs on this machine.

**A scheduled job fails where nobody is looking, so this one leaves a note.**

- A run that fails writes `brain/.refresh-failed`, naming the step that failed, and the
  session-start hook prints it at the top of your next session. Fix the cause and run the
  command by hand; a clean run removes the note.
- A schedule that never starts cannot write that note. That case is caught by age instead:
  once the last ingest is 7 days old, session start says the brain is stale. Change the number
  with `PROJECT_BRAIN_STALE_DAYS`; `0` turns the line off.
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
