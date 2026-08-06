---
name: bug-report
description: Structured bug-fix protocol - collect repro details, find the root cause, fix, append to common-gotchas. Use when told 'I found a bug', 'something is broken', 'fix this bug', 'this is broken', or given any bug report.
---

Cursor does not auto-load Claude Code skills, so this is a router. The procedure lives in one
place and every harness points at it - never fork the body into this file.

Read `.claude/commands/bug-report.md` and the full protocol it wraps,
`docs/methodology/bug-protocol.md`. Follow it without being asked to: if repro details are
missing, ask for them first.
