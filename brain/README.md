# Project Brain

An optional local knowledge base: BM25 keyword search over your project corpus (docs, commit
history, agent memory), auto-injected into every Claude Code prompt via a UserPromptSubmit hook.

Based on the "Second Brain" pattern: a `raw/` corpus of copied source material, indexed with
[QMD](https://www.npmjs.com/package/@tobilu/qmd), searched at prompt time in ~1-2 seconds.

**Off by default.** The hook exits silently until you initialize (it checks for `.last-ingest`).
If this project doesn't need a knowledge base yet, delete this directory - nothing else depends
on it.

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

Re-run step 3 whenever the corpus should refresh (or schedule it).

## Layout

```
brain/
├── config.sh        # what gets ingested (edit this)
├── scripts/ingest.sh # copies sources into raw/, secret-scans, stamps .last-ingest
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
2. **Periodic ingest** - a scheduled task that re-runs ingest + index daily.
3. **A lint pass** - an agent skill that checks the brain for contradictions, stale claims, and
   broken cross-references before each monthly summary refresh.
4. **External sources** - issue-tracker exports and knowledge-base pages copied into `raw/` by an
   agent with the relevant MCP access (they can't be fetched by a plain shell script).
