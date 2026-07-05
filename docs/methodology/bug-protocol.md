# Bug-Fix Protocol

The canonical bug workflow; the `/bug-report` slash command (Claude Code) is a thin wrapper around
this file. Agents follow this automatically when given a bug report — the user should never have
to invoke it by name.

## Collect first

Collect the following before attempting any fix:

1. **What you were doing** (screen, action, account/user):
2. **What you expected**:
3. **What actually happened** (error message, visual glitch, crash):
4. **Logs** (terminal, error tracker, browser console — or "none"):
5. **Reproducible?** (always / sometimes / once):

Ask for any missing details. Do NOT guess or start fixing until you have at least items 1-3.

## Fix protocol

Once you have the report, follow this sequence strictly:

1. **DIAGNOSE** — Read logs, check the error tracker, check `docs/common-gotchas.md` for known
   issues
2. **REPRODUCE** — Confirm the bug exists and identify the exact trigger
3. **LOCATE** — One targeted search for the error. Do not search for the same thing twice.
4. **ROOT-CAUSE** — Understand *why* it breaks, not just *where*
5. **FIX** — Minimal change, one file if possible
6. **TEST** — Write or update a test that would have caught this
7. **VERIFY** — Run lint + the test suite, confirm the fix works
8. **REPORT** — Tell the user: what broke, why, what changed, and what test was added
9. **LOG** — Append the symptom / root cause / fix to `docs/common-gotchas.md`

**Hard bug?** If it resists this protocol — can't reproduce, no obvious root cause, a performance
regression, or flaky/intermittent — switch to a feedback-loop-first discipline: build a tight,
re-runnable repro *before* theorizing. Return here for TEST/LOG once the fix lands.

## NEVER

- Never fix without reading the error first
- Never search for the same thing twice
- Never rebuild without a theory of what's wrong
- Never add logging before checking existing logs
- Never claim "fixed" without verification
