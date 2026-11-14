# Changing the rules agents load

`AGENTS.md`, `CLAUDE.md` and any other always-loaded rule file are read into every session and
every unattended run, so each line costs context everywhere, and each edit changes the behavior
of every agent at once. Two habits keep changes to them honest: measure before you trim, and
prove a behavioral edit with a blinded comparison before you ship it.

## Measure before trimming an always-loaded file

The intuition is that a rule file is mostly history - dates, incident notes, "added after X" -
and that moving it out is the big win. Measure it before you act on that. In the project this
template came from, a trim was planned on exactly that assumption; moving every history and
provenance sentence out of the two root rule files saved **5.3%** of their bytes, because an
earlier pass had already taken most of it and what remained was live rule text. The same session
cut **18.6%** by a different move.

- **Test each line before you keep it: can the agent find this out by reading the code, and
  does every task need it?** A line earns a place in an always-loaded file only when the answer
  is no and then yes: it cannot be discovered, and it applies everywhere. A fact the agent would
  find in `package.json` fails the first half. A rule that matters only when writing a migration
  fails the second, and belongs in a doc the file points to with a line that says *when* to read
  it ("before writing a migration, read `docs/migrations.md`"). This is also the reason to skip
  a tool's "generate my rules file" command (`/init` in Claude Code): it writes down what it
  found in the code, which is the half that needed no writing down.
- **Count bytes first.** `wc -c` on every file the trim touches (for the two root files,
  `wc -c AGENTS.md CLAUDE.md`), before and after, in the commit message. A trim with no number
  cannot be compared with the next one.
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
- **A passing "nothing was deleted" check is not that re-check.** A script can prove every moved
  line still exists somewhere; it cannot prove a rule an implementing session needs is still in
  the file that session loads. Get a fresh-context review of the trimmed file against the old
  one, asking only "which rule did a session lose?". In the source project the first draft of a
  rationale move cut 13% with such a checker green, and the review found several live rules that
  had moved out with the history; they went back, and the final cut was 8%.
- **Mind the harness byte limits.** Some harnesses stop reading a rule file at a fixed size and
  say nothing (Codex: `project_doc_max_bytes`, see `.codex/README.md`). A file that grew past the
  limit has already lost its tail in every session that loads it. `bin/check-instruction-budgets.sh`
  fails CI before that happens on the Linux checkout, for the files and sums listed in
  `bin/instruction-budgets.txt` only. The shipped list names the root `AGENTS.md`; add each nested
  `AGENTS.md` with its `sum` line, or the check never measures it. A Windows checkout with CRLF line endings
  is a byte per line larger, so leave headroom.

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
   rule is inert. That blocks claiming an addition works; it does not block a removal (see
   below).

**The promote condition depends on the direction of the edit:**

- **An edit that only removes or softens text ships on a tie.** "No measurable effect" means the
  text was costing context in every session for nothing. Two removed gates of the "NEVER do X /
  if you catch yourself, STOP" kind tied exactly across 16 runs, and were cut.
- **An addition, or a rewrite meant to change behavior, must show an effect.** If it ties, drop
  it: a rule that changes nothing measurable is cost with no benefit, however right it reads.

A removal ships on any tie, including a ceiling tie where every run passes on both arms: the
burden of proof sits with the text that costs context in every session, so "could not show a
difference" is enough to cut it. A ceiling tie only blocks claiming that an addition works.

The comparisons also surface findings worth more than the edit itself. In one round, every run
of a smaller model stopped to ask for plan approval when run unattended, under a "plan first,
confirm before implementing" rule, while every run of a larger model finished. Any unattended
job that inherits an interactive rule like that needs its own explicit "no stops" line.
