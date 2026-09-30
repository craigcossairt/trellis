---
name: trellis-survey
description: Check this template's static wiring and setup - missing hooks, unreachable skills, unfinished context files. Runtime activation and trust require separate checks. Read-only. Use when asked "what do I have", "is everything set up", "what is actually running", "audit my setup", "did I break anything", "what did I delete".
---

# What this copy has, and how it is wired

```bash
bash bin/trellis-survey.sh
```

Exit **0** nothing to report, **1** there are findings, **2** could not run.

**Exit 2 is not a clean bill of health.** The survey could not complete its
checks, which is different from finding no problems. Report it as what it is.

## The rule

**You do not decide what is wrong. The script does.** Read its output and relay
it. Do not go looking for additional problems by eye and mix them into the
report - if the survey should catch something it does not, that is a change to
the script, not a thing you improvise on top of it.

## It is read-only, and that is the point

It writes nothing, deletes nothing and fixes nothing. Every finding is a
decision for the person. Most of them have a perfectly good answer of "yes, I
deleted that on purpose".

So: **report first, offer second, and never fix as part of surveying.** If they
want something fixed, that is a separate action they ask for after seeing the
list.

## What the findings mean

| Heading | What it means | Why it matters |
|---|---|---|
| NOT RUNNING | The harness or git calls something that is not there, or will skip it | This is the dangerous one. A missing hook does nothing and says nothing, so it looks exactly like a working hook |
| PRESENT BUT INERT | A script is on disk and nothing invokes it | Harmless, but it reads as protection that does not exist |
| HARNESS COVERAGE | Missing or invalid routes in a retained adapter | A skill with no Cursor or Codex router is invisible there; a router with no skill is a dangling pointer |
| SETUP UNFINISHED | `FILL IN` markers left | Every one is a question the agent answers by guessing, in every session |
| TEMPLATE STATE | Version, and template files no longer present | Usually deliberate deletion. Listed so "I thought that was still here" has an answer |

Lead with **NOT RUNNING**. Those are the ones where somebody believes they are
protected and is not. The rest can be a short list underneath.

## Limits to state rather than hide

- Claude hooks are matched against `settings.json` by **basename**, not by parsing the
  JSON, because there is no guarantee `jq` exists on a fresh machine and a
  missing `jq` must not quietly turn the check into a pass. A hook wired under a
  different path with the same basename therefore reads as wired.
- Codex uses `bin/validate-codex.py` to check JSON, event wiring, known script
  targets, router frontmatter, and coverage. It does not execute or interpret
  arbitrary shell commands. Python is needed only while a Codex adapter remains.
- The survey checks **static wiring, not runtime behavior or trust**. A hook
  can pass this check and never run in an untrusted session. Follow `SETUP.md`'s
  live checks with dummy files and inspect the hook verdict; a prose refusal
  from the agent is not evidence that the hook ran.

## After the report

If setup is unfinished, offer `/setup`. If the template state shows a version,
mention `/trellis-sync` will say what has changed upstream since. Do not run
either one without being asked.
