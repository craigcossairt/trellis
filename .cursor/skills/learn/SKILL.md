---
name: learn
description: Review the current conversation and update project knowledge - common-gotchas.md (bug patterns), AGENTS.md (conventions), agent memory (cross-session). Use when asked 'what did we learn', 'capture lessons', 'update common-gotchas', or at the end of a debugging session.
---

Cursor does not auto-load Claude Code skills, so this is a router. The procedure lives in one
place and every harness points at it - never fork the body into this file.

Read `.claude/skills/learn/SKILL.md` and follow it. Note the write-time invalidation pass:
when a new fact contradicts a recorded one, supersede the old entry in the same session.
