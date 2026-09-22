---
name: setup
description: Walk a new project through setting up this template - interview the owner, fill in the context files, wire the safety rails, and verify it worked. Use when asked to "set up trellis", "set up this template", "walk me through SETUP.md", "help me get started", "configure this project", "initialise the template".
---

# Set this template up, by interview

`SETUP.md` is a checklist a person works through alone. This runs the same
checklist as a conversation: you ask, they answer, you write the files.

**`SETUP.md` is the script. Read it now and follow ITS steps and ITS order.**
Nothing below repeats its content, deliberately - a copy here would drift from
the real checklist within one edit, and then two files would disagree about what
setup is. This file only covers how to *conduct* it.

## Before anything: one question, then calibrate

Ask both of these in a single `AskUserQuestion` call, before reading anything
else or touching a file.

1. **How much have you built before?** Offer: *first real project* / *I code,
   new to working with an agent* / *I do this for a living*.
2. **What are you making, in a sentence?**

Their first answer sets your verbosity for the whole session, and this is the
main thing the skill exists to get right:

| They said | How to talk for the rest of setup |
|---|---|
| First real project | Explain what each thing IS before asking about it, in one or two plain sentences. No jargon without a gloss. Say why a step matters and what breaks without it. Offer a sensible default for every question so they can say "that one". |
| New to agents | Assume the engineering, explain the agent-specific parts: what a hook is and when it fires, why context files beat re-explaining every session, what a skill is. |
| Professional | Terse. Ask, take the answer, move on. Skip the rationale unless they ask or unless a choice is genuinely non-obvious. |

Whatever they said, never make them read a file to answer a question. You have
read it; put the choice to them in their own terms.

## How to run each step

- **Ask, then write.** Never leave a `<!-- FILL IN -->` for them to find later.
  The whole point is that they finish this conversation with the files filled.
- **Batch related questions into one `AskUserQuestion` call.** A separate round
  trip per field is how a five-minute step becomes twenty.
- **Recommend, do not present a menu.** Lead with the option you would pick and
  say why in a clause. "Menu with no recommendation" is the failure mode that
  makes a beginner guess.
- **One step at a time, in `SETUP.md` order.** Say which step you are on and
  roughly how far in they are. Let them stop and resume.
- **Their answers are the source, not your inference.** If they told you the
  stack, write that. Do not upgrade it to what you would have chosen.
- **A question you can answer yourself is not a question.** Read the repo. If
  `package.json` names the framework, do not ask what the framework is; confirm
  it in passing.

## The things you must not do

- **Never put a real secret in a file.** You may create `.env` from
  `.env.example` and name the variables. The *values* are theirs to paste, and
  you say so. This is not a formality: the sensitive-file hook exists to stop an
  agent writing there, and setup is not an exemption.
- **Never run `bin/trellis-manifest.sh --write`.** It records this project's
  tree as though the template had shipped it, which makes their own files show
  up as template files on every later sync. It now refuses to run here, and you
  should not reach for `--force` to get around it.
- **Never write `.trellis/baseline`.** Nothing reads it, and the sync tool
  deliberately removed support: with whole-file updates, a "baseline" would make
  everything they fill in during setup classify as safe for the template to
  overwrite. Their filled-in `AGENTS.md` should read as *theirs*, which is what
  happens when no baseline exists.
- **Never delete a file they have not agreed to delete.** Step 5 of `SETUP.md`
  is a list of things they *may* remove. Ask per item, and take silence as keep.
- **Do not install anything without asking**, and name what it costs - money,
  an account, or a background process.

## Filling `AGENTS.md`

This is the step that pays for the whole session, and the one most likely to be
rushed. The `<!-- FILL IN -->` markers are the required set, but they are the
floor. What makes the file worth having is the part no marker asks for: the two
or three conventions this project has that the next session could not guess.

Ask for them directly, in their language. "Is there anything about this project
that has already bitten you, or that you would have to explain to a new person
on day one?" Whatever comes back goes in. If nothing comes back, that is a fine
answer on day one - leave it and say `/learn` will fill it as they go.

For the model-tier table, ask which models they actually have access to rather
than filling in the current frontier names. A table naming a model they cannot
call is worse than an empty one.

## Tooling and services

`docs/recommended-tooling.md` is the catalogue. Read it; do not recite it.
Filter to their project from their one-sentence answer, and to their level:

- **First project:** the two or three things that prevent real pain, with what
  each one is for. A long list is how someone ends up with five accounts and no
  project.
- **Experienced:** the catalogue's own overlap-and-collision section matters
  more than the recommendations. Say what would collide with what they already
  run.

Always name the free tier and whether an account is needed. Never sign them up
for anything.

## Finish by proving it works

`SETUP.md` ends with checks. Run them rather than describing them, and report
what actually happened.

The load-bearing one is asking the agent to edit `.env` and confirming it
refuses. A hook that silently is not wired looks exactly like a hook that is
working, right up until it matters. If it does not refuse, that is the finding -
say so plainly and fix it before calling setup done.

Then write their first `docs/decision-log.md` entry: what they decided to build
and why, in their words. It is the first thing future-them will read.

## Last

Tell them three things, briefly:

1. What you filled in, and where it lives.
2. What you deliberately left empty, and what fills it (`/learn` after a bug,
   the decision log as they go).
3. That the template can be re-synced later with `/trellis-sync`, and that their
   edits are protected because the manifest records what the *template* shipped.
