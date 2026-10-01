# Changing the rules agents load

`AGENTS.md`, `CLAUDE.md` and any other always-loaded rule file are read into every session and
every unattended run, so each line costs context everywhere, and each edit changes the behavior
of every agent at once. Two habits keep changes to them honest: measure before you trim, and
prove a behavioral edit with a blinded comparison before you ship it.

## Measure before trimming an always-loaded file

The intuition is that a rule file is mostly history - dates, incident notes, "added after X" -
and that moving it out is the big win. Measure it before you act on that. In the project this
template came from, a trim was planned on exactly that assumption; moving every history and
provenance sentence out of the two root rule files saved **about 5%**, because an earlier pass
had already taken most of it and what remained was live rule text. The same session cut nearly
**19%** by a different move.

- **Count bytes first.** `wc -c AGENTS.md CLAUDE.md` before and after, in the commit message.
  A trim with no number cannot be compared with the next one.
- **Dedupe a pointer row against the file it points to.** A table row or bullet that says
  "use skill X when Y" and then restates X's procedure is paying twice: the harness often loads
  the skill's own description every turn anyway. Cut the row to its trigger and the rules a
  session needs *without opening the file*. Before dropping each fact, check the target file
  actually carries it; where it does not, the fact stays in the row.
- **Move history, don't delete it.** Rationale and incidents go to a history or decision doc the
  rule file points to, recorded as they were.
- **Re-check what the cut removed.** In the same trim, one row lost the words "two independent
  checks with independent bypasses", and an agent given the trimmed file then claimed one bypass
  skipped both checks. A short phrase can be the only thing ruling a wrong reading out.

## Prove an agent-rule edit with a blinded A/B

A rule edit is a claim that agents will behave differently. Reading the new wording and finding
it convincing is not evidence; a run is. Before promoting a substantive edit to a skill, a
protocol or a rule file:

1. **Fix the task, the rubric and the graders before any run.** Write the scoring rubric and
   the margin you will treat as "no difference" first. Changing either after seeing outputs
   turns the eval into a story.
2. **Run each arm as a separate CLI process** (e.g. `claude -p`), in a directory that does not
   load the live rule files. An in-session subagent inherits the session's own instructions,
   including the version under test, which contaminates the control arm.
3. **Randomize which version each run gets**, and record the assignment where the grader cannot
   see it. Several runs per arm, not one.
4. **Grade blind.** The grader (ideally a different model from the one that ran the task, see
   `adversarial-review.md`) sees outputs and the rubric, never which version produced what.
5. **Read the outputs, not only the scores.** Check that the task could have shown a difference
   at all: if every run on both arms passes, a tie says the task was too easy, not that the
   rule is inert.

**The promote condition depends on the direction of the edit:**

- **An edit that only removes or softens text ships on a tie.** "No measurable effect" means the
  text was costing context in every session for nothing. Two removed gates of the "NEVER do X /
  if you catch yourself, STOP" kind tied exactly across 16 runs, and were cut.
- **An addition, or a rewrite meant to change behavior, must show an effect.** If it ties, drop
  it: a rule that changes nothing measurable is cost with no benefit, however right it reads.

The comparisons also surface findings worth more than the edit itself. In one round, every run
of a smaller model stopped to ask for plan approval when run unattended, under a "plan first,
confirm before implementing" rule, while every run of a larger model finished. Any unattended
job that inherits an interactive rule like that needs its own explicit "no stops" line.
