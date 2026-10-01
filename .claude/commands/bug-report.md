---
description: Structured bug-fix protocol per docs/methodology/bug-protocol.md. Use when asked to '/bug-report', 'I found a bug', 'something is broken', 'fix this bug', 'report a bug', 'this is broken'.
---

Follow the full protocol in `docs/methodology/bug-protocol.md` - read it now if it isn't already
in context.

Non-negotiables (details in the doc):

- Collect what/expected/actual before touching anything; ask for missing details
- Check `docs/common-gotchas.md` for the symptom before diagnosing from scratch
- DIAGNOSE → REPRODUCE → LOCATE → ROOT-CAUSE → FIX → TEST → VERIFY → REPORT → LOG (the usual
  order, not a script: go back a stage when a finding changes the theory; strengthen an
  existing test that passed despite the bug before adding a new one)
- Append the symptom / root cause / fix to `docs/common-gotchas.md` when done
- Never claim "fixed" without verification
