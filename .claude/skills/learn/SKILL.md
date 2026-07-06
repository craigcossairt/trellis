---
name: learn
description: Review the current conversation and update project knowledge artifacts - common-gotchas.md (bug patterns), AGENTS.md (conventions), agent memory (cross-session). Use when asked to '/learn', 'what did we learn', 'capture lessons', 'update common-gotchas'.
disable-model-invocation: true
---

You are closing the learning loop. Review this conversation for things worth capturing, then
update the right artifacts so the learning survives into future sessions.

## What to look for

Scan the conversation and classify any of these as candidates to capture:

1. **Bug patterns** - a symptom someone ran into, a root cause, and a fix that should be visible
   to the next person who sees the same symptom.
2. **Tool gotchas** - something about a tool, framework, or service that surprised you and would
   surprise the next session.
3. **Conventions** - a decision about how code should look or how work should flow in this repo,
   validated in this session.
4. **Cross-session knowledge** - user preferences, working-style feedback, project milestones.
5. **Context drift** - anything you noticed is stale in existing docs.

Things to SKIP:
- Transient task state ("we're in the middle of X")
- Stuff already documented elsewhere (check before duplicating)
- Vague observations ("this could be cleaner")
- Conversation turns that were noise

## Where each type goes

| Type | Target | Action |
|---|---|---|
| Bug pattern | `docs/common-gotchas.md` | Append a row using the file's format. Include commit SHA + issue ID if known. Auto-apply. |
| Tool gotcha | `docs/common-gotchas.md` (or agent memory if not project-specific) | Auto-apply. |
| Convention | `AGENTS.md` | Propose the diff to the user first - do NOT auto-edit AGENTS.md. |
| Cross-session knowledge | Your harness's persistent memory, if available | Auto-apply per its conventions. |
| Context drift | Flag to the user | Don't fix silently; say what's stale and where. |

## Process

1. **Read the conversation above.** Identify 0-5 capture candidates. Don't force it - if nothing's
   worth saving, say so and exit.
2. **Check for duplicates** before writing. Grep `common-gotchas.md` and memory for the same
   symptom/topic. If already documented, skip (or propose an update instead of a new entry).
3. **For auto-apply categories** (bug patterns, tool gotchas, cross-session knowledge): make the
   edits, then list them in the output.
4. **For propose-first categories** (conventions): show the proposed diff and ask for approval
   before editing.
5. **At the end**, output a short summary:
   - **Captured:** X entries applied (list files + one-line descriptions)
   - **Proposed:** Y edits waiting on approval
   - **Drift flagged:** Z (list files that look stale)
   - **Nothing worth capturing:** if that was the outcome, say so plainly.

## Constraints

- **Brevity.** Each captured entry should be terse - one row in a table, a short memory note.
  Future sessions are the consumer; they have limited attention budget.
- **Cite sources.** If you're recording "the user said X," quote the message.
- **Don't rewrite history.** When updating an existing entry, add new info - don't delete old
  context unless it's wrong.
- **Respect the sensitive-file hook.** Don't try to edit .env, lock files, or generated files.
