---
name: setup
description: Walk a new project through setting up this template - interview the owner, fill in the context files, wire the safety rails, and verify it worked. Use when asked to "set up trellis", "set up this template", "walk me through SETUP.md", "help me get started", "configure this project", "initialise the template".
---

# Set this template up, by interview

`SETUP.md` is a checklist a person works through alone. This runs the same
checklist as a conversation: you ask, they answer, you write the files.

**`SETUP.md` is the script.** Nothing below repeats its content, deliberately -
a copy here would drift from the real checklist within one edit, and then two
files would disagree about what setup is. This file only covers how to *conduct*
it.

Order of operations, and it only goes this way round:

1. Ask the two calibration questions below. Nothing else first.
2. Read `SETUP.md`.
3. Work its steps, in its order, as an interview.

Asking first is not a stylistic preference. Their answer decides how much you
explain at every step after it, so reading the checklist first means drafting
the whole conversation for a reader you have not met yet.

## 1. Before anything: two questions, then calibrate

Ask both of these together using the available question tool (or in conversation
if the tool has none), before reading `SETUP.md` or touching any file. Do not
depend on a tool name specific to one coding agent.

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

## 2. How to run each step

- **Ask, then write.** Never leave a `<!-- FILL IN -->` for them to find later.
  The whole point is that they finish this conversation with the files filled.
- **Batch related questions into one question-tool call or message.** A separate round
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
- **Never change a GitHub setting, star a repository, or create a scheduled job
  without a yes to that one thing.** Each of those acts outside this folder, on
  their account or their computer. A yes to one is not a yes to the next.

## Filling `AGENTS.md`

This is the step that pays for the whole session, and the one most likely to be
rushed. The `<!-- FILL IN -->` markers are the required set, but they are the
floor. What makes the file worth having is the part no marker asks for: the two
or three conventions this project has that the next session could not guess.

Ask for them directly, in their language. "Is there anything about this project
that has already bitten you, or that you would have to explain to a new person
on day one?" Whatever comes back goes in. If nothing comes back, that is a fine
answer on day one - leave it and say `/learn` will fill it as they go.

For the model-tier table, ask which model families they actually have access to
and fill in the family or alias their tool takes (e.g. `haiku`, `sonnet`, `opus`),
never a version. A table naming a model they cannot call is worse than an empty one.

When the file is filled, run `bash bin/check-instruction-budgets.sh`. The
template ships close to the size one tool (Codex) will load, and filling the
slots makes the file longer. Past that size the tool drops the end of the file
and says nothing. If the check fails, move the longest explanation they will not
need in every session out to `docs/`, and leave a one-line pointer that says
when to read it. Do not raise the budget to make the check pass.

## Tooling and services (step 6)

This step is a conversation you start, not a file you point at. The owner will
not open `docs/recommended-tooling.md`, and cannot ask for a tool they have
never heard of. One person setting this template up had to tell their agent,
unprompted, that they wanted Linear and Matt Pocock's skills. Both were on the
list. Nobody had offered them.

Read the catalogue, starting with its **Start here** table. Then put a shortlist
to them:

- **One recommendation per row that fits their project**, from their
  one-sentence answer and what the repo shows. For each: what it is for, what it
  costs, whether it needs an account, and either "now" or "later, when X". Leave
  out rows that do not fit; do not list them and wave them away.
- **Always raise these by name**, whatever the project: where their secrets
  live, the issue tracker (GitHub Issues, or Linear), and Matt Pocock's skills.
  Add T3 Code if they run more than one session or more than one AI tool.
- **Ask what they already use, and what they have heard of and want.** Their
  answer outranks the catalogue's pick.
- **First project:** two or three "now" items at most, each with what it
  prevents. Everything else is a "later" with its trigger. A long list is how
  someone ends up with five accounts and no project.
- **Experienced:** the catalogue's overlap-and-collision section matters more
  than the recommendations. Say what would collide with what they already run.

Then act on the answers:

- Install only what they said yes to, one at a time. Read that entry's notes
  first and do what they say (for Matt Pocock's skills: settle which test-first
  workflow is the authority, and move the block its setup skill writes out of
  `CLAUDE.md` and into `AGENTS.md`).
- Write the picks into `AGENTS.md`: the Tech Stack table and the issue-tracker
  pointer. A tool the context file does not name is one the next session will
  not use.
- Put the "later" items in one `docs/decision-log.md` entry, each with the
  event that would trigger it.

Always name the free tier and whether an account is needed. Never sign them up
for anything.

## Project memory (step 7)

Do not ask whether they "want a knowledge base". Work out whether `brain/` would
help this project, then recommend one of the three outcomes `SETUP.md` names.

Measure before you ask anything:

- **Their own documents.** Tracked markdown the template did not ship:
  `git ls-files '*.md' | grep -vxFf <(cut -d' ' -f2- .trellis/manifest) | wc -l`
- **History.** `git rev-list --count HEAD`, and the first commit's date from
  `git log --reverse --format=%as | head -n 1`. A project made by cloning or
  forking the template carries the template's own commits, which are not
  theirs: when the tag named by `version=` in `.trellis/source` exists here
  (`git rev-parse -q --verify "refs/tags/<version>"`), count from it instead,
  with `<version>..HEAD` in both commands.
- **Their tool.** `docs/harness-support.md` says which tools get `brain/`
  context added to prompts on their own. In the others the index still builds
  and is searched by hand, which is a weaker case for setting it up.

Then ask the one thing the repo cannot tell you: is there material outside it
they would want you to know (specs, research, notes, an export from another
tool), and do they plan to write things down here as they build?

Give the recommendation in one sentence, with the numbers: "You have 23
documents of your own and four months of history, so I would set it up now."
Never present the three outcomes as a menu.

- **Now:** follow `brain/README.md`. It installs two things (bun and QMD), so
  ask first. Finish by running a real search and showing a hit: from their own
  docs when they have some, otherwise from the methodology docs the template
  shipped, and say which it was.

  Then propose the daily refresh. Say what it is: a scheduled job on their
  computer that runs one command a day. On a yes, run the lines under
  **Keeping it current** in `brain/README.md` for their operating system, as
  written and in order. Do not improvise a different schedule line: the ones
  there carry the `PATH` a scheduler does not have, and a line without it
  works by hand and fails on its first scheduled run.
  1. `bash brain/scripts/refresh.sh` by hand, ending `brain refresh: done.`
  2. The run that proves the scheduler's own environment works: step 1 of the
     cron lines, or the started task on Windows. It counts only when
     `brain/log.md` gained a new `refresh - ok` line from that run.
  3. Read the entry back and show it to them.

  Report the schedule as working only after step 2. If it fails, say so, show
  what it printed, and ask whether to leave the job or remove it. If they say
  no to the schedule, tell them session start will say when the index is a
  week old, in the tools that run that hook.
- **Later:** write the trigger into `docs/decision-log.md` in their words. A
  "later" with no trigger is a "never".
- **Delete:** only on their say-so, like every other deletion.

## Repository settings (step 8)

Run `bash bin/check-repo-settings.sh`. It only reads.

- **Exit 2 means it could not tell.** With no table printed, nothing was
  read: say why in their terms (the GitHub tool is not installed or not signed
  in, the project has no `origin` remote on github.com yet, they do not
  administer the repository) and record the step as not checked. With a table and an
  `UNKNOWN` line in it, only that setting could not be read: handle the other
  lines as usual and report that one as not checked, with the reason its line
  gives. Never report an unread setting as fine, and do not treat exit 2 as a
  reason to stop setup.
- **For each `OFF` line:** one sentence on what it protects against, your
  recommendation, then ask. On a yes, run the one command the script printed
  for that setting, or give them the settings page when that is what it
  printed. Afterwards run the script again and report what it now shows. A
  command that returned without an error has not proved the setting changed.
- **One yes per setting.** For a first-timer, take them one at a time. For a
  professional, show the whole table and ask which.
- **`SKIP`** is a plan or visibility limit. Say so and move on. Do not suggest
  buying a plan.

Then `.github/dependabot.yml`. The script's `dependabot-config` line names
what the file watches today. Read the repo for the package managers it uses
(`package.json`, `pyproject.toml`, `pubspec.yaml`, `Cargo.toml`, `go.mod`,
`Gemfile`), and for each one the file does not watch, propose the entry and
say what it brings: a pull request, at most weekly, when one of those packages
has a newer release. Add it on a yes, as a whole entry shaped like the shipped
one: GitHub requires a `directory` and a `schedule` on each, and the script
reports the file as `OFF` when an entry lacks either, so run it again
afterwards. If the project has no package manager
yet, say that the entry gets added when the first one appears, and leave the
file alone. Say once what the shipped entry does, since they did not choose
it: the same weekly pull request for the GitHub Actions in the template's own
workflow, which they can keep or delete with the file.

## Finish by proving it works

`SETUP.md` ends with checks. Run them rather than describing them, and report
what actually happened.

For a tool with edit hooks, use a disposable `.env` containing only dummy values
and exercise the guarded edit tool. Check the hook's actual blocking verdict;
an agent refusing in prose does not prove that a hook ran. Never use real
credentials for this check. Report missing activation or a failed block and fix
it before claiming that protection works. For an adapter without edit hooks,
report that limitation and verify the Git gate separately.

`SETUP.md` step 2 had them write the first `docs/decision-log.md` entry, and
steps 6 and 7 may have added the "later" ones. Check that the first entry is
there, and write it now if it was skipped. Do not write an entry that
repeats one already in the file.

## Last

Tell them three things, briefly:

1. What you filled in, and where it lives.
2. What you deliberately left empty, and what fills it (`/learn` after a bug,
   the decision log as they go).
3. That the template can be re-synced later with `/trellis-sync`, and that their
   edits are protected because the manifest records what the *template* shipped.

Then, once, and only after the checks passed: if the template was useful to
them, ask whether they would star it on GitHub, because stars are how other
people find it. One sentence, no pitch.

- Skip the ask entirely when this checkout's `origin` is the upstream named in
  `.trellis/source`. That is the maintainer.
- On a yes, with `gh` signed in: `gh api -X PUT user/starred/<upstream>`, using
  the `upstream=` value from `.trellis/source`, and report whether it succeeded.
  Without `gh`, give them the link.
- On a no, or no answer, drop it. Do not ask again.
