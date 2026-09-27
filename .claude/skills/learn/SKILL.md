---
name: learn
description: Review the current conversation and update project knowledge artifacts - common-gotchas.md (bug patterns), conventions at the highest rung that holds them (code, check, reviewer standard, skill, then AGENTS.md), navigation pointers, agent memory (cross-session). Use when asked to '/learn', 'what did we learn', 'capture lessons', 'update common-gotchas'.
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
6. **Navigation miss** - the agent went looking for something (a file, a command, which module
   owns a concern) and took several tries or guessed. The fix is usually a one-line pointer where
   the agent looked first, not a new rule.
7. **Tool economy** - a tool or pattern that burned tokens for little: re-reading a whole large
   file, a noisy command output, a search repeated because its first result was not trusted.
   Propose the cheaper form, or a script that returns just the answer.
8. **Steering bloat** - a skill, command or rules section that was loaded but did not help, or
   that contradicted another. Everything always loaded costs context on every session, so a
   shorter file is a fix.

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
| Convention | **The rung the correction ladder (below) picks.** Only rung 5 goes in `AGENTS.md`. | Propose first; on approval, apply it in this run. |
| Cross-session knowledge | Your harness's persistent memory, if available | Auto-apply per its conventions. |
| Context drift | Flag to the user | Don't fix silently; say what's stale and where. |
| Navigation miss | A pointer where the agent looked first (the relevant AGENTS.md section, a doc's index, a skill's opening lines) | Propose first. One line that points, not one that explains. |
| Tool economy | The skill or command that caused it, or a small script | Propose first. |
| Steering bloat | The bloated file | Propose the cut or move as a diff. Never delete a rule without saying where its content went. |

## The correction ladder (conventions only)

A convention written as prose is the weakest fix there is. Agents copy what the code already
does, and a rule in `AGENTS.md` is one they may never read: the same mistake gets made again
after the rule against it is written down. So before proposing a convention, climb this ladder
from the top and stop at the first rung that can hold it:

1. **Make it impossible in code.** A type, a required parameter, a wrapper that does the right
   thing by default. The mistake then cannot be written.
2. **A deterministic check.** A lint rule, a CI step or a ratchet. It fails the build instead of
   hoping someone remembers. When a bad pattern already exists and cannot be cleaned up now, a
   ratchet at today's count still stops it spreading.
3. **A reviewer standard.** A judgment call no script can make goes in `docs/coding-standards.md`,
   which the review agent reads. Never fall back to `AGENTS.md` for these: that is the
   implementer's always-loaded context, which this rung exists to keep them out of.
4. **A skill or command step**, when the lesson is a procedure rather than a property of the code.
5. **`AGENTS.md` prose, last resort**: only a navigation pointer, or a rule every implementing
   session needs up front.

The proposal names its rung and gives one line for why each higher rung does not work ("a check
cannot tell X from Y because..."). A proposal that goes straight to rung 5 without those lines is
incomplete. A rung-1 or rung-2 fix is code, so propose it as an issue or follow-up change rather
than writing it inside `/learn`. A rung-3, 4 or 5 fix is text: once the user approves it, apply
it in the same run.

## Process

1. **Read the conversation above.** Identify 0-5 capture candidates. Don't force it - if nothing's
   worth saving, say so and exit.
2. **Supersession pass (write-time invalidation).** Before writing each capture, search for what
   it touches: grep `common-gotchas.md` and memory for the same symptom/topic (and query the
   project brain, if initialized). Three outcomes:
   - **Already documented and still true** - skip, or fold new detail into the existing entry.
   - **Documented but now contradicted or outdated** - update the OLD artifact in the same
     session. Correct it in place, or when the old fact has historical value, mark it superseded
     instead: if your memory format supports metadata, add `superseded_by: <successor>` and keep
     the file; for gotchas/docs, edit in place - git history preserves the old text. Never write
     the new fact and leave the contradicted one live; retrieval and future greps will keep
     serving it.
   - **Net-new** - write fresh.
3. **For auto-apply categories** (bug patterns, tool gotchas, cross-session knowledge): make the
   edits, then list them in the output.
4. **For propose-first categories** (conventions, navigation misses, tool economy, steering
   bloat): show the proposed diff and ask for approval before editing, then apply what is
   approved in this run.
5. **At the end**, output a short summary:
   - **Captured:** X entries applied (list files + one-line descriptions)
   - **Superseded:** entries invalidated/updated by this session's captures (list old -> new)
   - **Proposed:** Y edits waiting on approval, each with its rung
   - **Drift flagged:** Z (list files that look stale)
   - **Nothing worth capturing:** if that was the outcome, say so plainly.

## Constraints

- **Brevity.** Each captured entry should be terse - one row in a table, a short memory note.
  Future sessions are the consumer; they have limited attention budget.
- **Cite sources.** If you're recording "the user said X," quote the message.
- **Don't rewrite history.** When updating an existing entry, add new info - don't delete old
  context unless it's wrong.
- **Respect the sensitive-file hook.** Don't try to edit .env, lock files, or generated files.
