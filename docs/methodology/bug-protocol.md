# Bug-Fix Protocol

The canonical bug workflow; the `/bug-report` slash command (Claude Code) is a thin wrapper around
this file. Agents follow this automatically when given a bug report - the user should never have
to invoke it by name.

## Collect first

Collect the following before attempting any fix:

1. **What you were doing** (screen, action, account/user):
2. **What you expected**:
3. **What actually happened** (error message, visual glitch, crash):
4. **Logs** (terminal, error tracker, browser console - or "none"):
5. **Reproducible?** (always / sometimes / once):

Ask for any missing details. Do NOT guess or start fixing until you have at least items 1-3.

## Fix protocol

Once you have the report, work through these stages. This is the usual order, not a script:
when a finding changes your theory, go back a stage.

1. **DIAGNOSE** - Read logs, check the error tracker, check `docs/common-gotchas.md` for known
   issues
2. **REPRODUCE** - Confirm the bug exists and identify the exact trigger
3. **LOCATE** - Follow the evidence from the symptom to the code that causes it. The line that
   reports an error is often not the line that causes it, so keep going past the first match
   until the mechanism is explained.
4. **ROOT-CAUSE** - Understand *why* it breaks, not just *where*
5. **FIX** - Minimal change, one file if possible
6. **TEST** - Write or update a test that would have caught this. **Strengthen before you
   add:** if an existing test covers this behavior and passed anyway, that test has the gap, so
   fix it rather than writing a new test beside it. Add a new test only when nothing covers the
   behavior.
7. **VERIFY** - Run lint + the test suite, confirm the fix works
8. **REPORT** - Tell the user: what broke, why, what changed, and what test was added or
   strengthened
9. **LOG** - Append the symptom / root cause / fix to `docs/common-gotchas.md`

**Hard bug?** If it resists this protocol - can't reproduce, no obvious root cause, a performance
regression, or flaky/intermittent - switch to a feedback-loop-first discipline: build a tight,
re-runnable repro *before* theorizing. Return here for TEST/LOG once the fix lands.

## Before you say "fixed"

Run the verification in step 7 and show its result. A fix that has not been run is a theory,
and the report should say so.

(This section used to be a five-line NEVER list, and step 3 said "search once". In a blinded
comparison, agents given either version all fixed the bug at its source, so the removed lines
changed nothing measurable while costing context in every session that loaded them. The one
line kept is the one that carries policy.)
