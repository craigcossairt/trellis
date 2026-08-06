---
name: review-dependency-updates
description: Review outdated dependencies, security-scan each candidate bump against OSV.dev, then apply only the safe updates and PR them. Use when asked to 'review dependency updates', 'what can be updated', 'are we exposed to <supply-chain attack>', 'bump dependencies safely'.
---

Cursor does not auto-load Claude Code skills, so this is a router. The procedure lives in one
place and every harness points at it - never fork the body into this file.

Read `.claude/skills/review-dependency-updates/SKILL.md` and follow it.
