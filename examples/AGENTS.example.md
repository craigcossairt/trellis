# AGENTS.md - Porchlight (FILLED EXAMPLE)

> This is a filled-in sample of AGENTS.md for a fictional project, so you can see what "done"
> looks like before editing your own. The real skeleton you should fill is `/AGENTS.md`.
> Delete this `examples/` folder whenever you like.

## Project

- **Name:** Porchlight
- **What it is:** A neighborhood tool-lending app - list what you own, borrow what you need
- **Owner:** Jordan Avery - jordan@porchlight.example
- **Stage:** prototype

## What I Need From Agents

- Research before advising - verify current facts (pricing, APIs, legal) before recommending
- When writing code, explain what you're doing and why in plain language
- If uncertain, say so explicitly - never fabricate facts or statistics
- Skip long preambles - get to the point
- Flag when professional review is needed (lawyer, accountant, security auditor)
- Default to actionable advice that can be executed this week

## Current State - Source of Truth Pointers

**This file does NOT own current priorities, active deadlines, or in-progress work.**

- **Active issues + priorities** - https://github.com/javery/porchlight/issues
- **Decision history** - `docs/decision-log.md`
- **Known bug patterns** - `docs/common-gotchas.md`

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 16 (App Router) |
| Backend | Supabase (Auth, Postgres, Storage) |
| Hosting | Vercel |
| Issue Tracking | GitHub Issues |
| Error Tracking | Sentry (not yet wired - waiting for first real users) |

## Getting Started

```bash
npm install          # install deps
npm run dev          # dev server on :3000
npm test             # vitest suite
npm run lint         # eslint + tsc
```

## Folder Structure

```
.
├── app/          # Next.js routes
├── components/   # shared UI
├── lib/          # Supabase client, domain logic (lending rules live here)
├── docs/         # gotchas, decision log, methodology
└── .claude/      # agent config
```

## Rules

(Working Methodology, AI Session Management, Delegation, Content Rules, and Autonomous
Housekeeping are kept exactly as the template ships them - most projects never need to change
those sections. The delegation table is filled like this:)

| Tier | Model (as of July 2026 - refresh when the family turns over) |
|---|---|
| Fast | Claude Haiku 4.5 |
| Mid | Claude Sonnet 5 |
| Strong | Claude Opus 4.8 |
| Frontier | Claude Fable 5 |
