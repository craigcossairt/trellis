---
name: tdd
description: Test-first workflow - red-green-refactor for every feature and bug fix. Use when asked to 'TDD', 'write the failing test first', 'red-green-refactor', 'test-first development', or before implementing any code change.
---

Cursor does not auto-load Claude Code skills, so this is a router. The procedure lives in one
place and every harness points at it - never fork the body into this file.

Read `.claude/commands/tdd.md` and the full methodology it wraps, `docs/methodology/tdd.md`.
Follow it end to end: one failing test at a time, confirm red before green, and mutate any
suite that guards a safety control before trusting it.
