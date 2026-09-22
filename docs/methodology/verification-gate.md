# Verification gates

Two gates, for two different questions that get confused with each other.

| | Answers | Runs |
|---|---|---|
| **Gate A** - write verification | Did the write I just made actually land? | After every mutation |
| **Gate B** - data-flow lock | Which findings are allowed to reach the conclusion at all? | Before synthesis, on fan-out results |

A task can need one, both, or neither. Both are fail-closed: unknown never
resolves to green.

**Reference this file. Do not restate it inside a skill.** The reason this
document exists is that the first gate had been hand-copied into several
procedures, each slightly different, and nobody could say which version was
the rule.

## When they apply

Gate A applies wherever an agent's judgment decides what gets written: a row in
a database, a row in a tracker, a file, an API call that changes something.

Gate B applies wherever you fan work out to subagents and then have a parent
decide what the findings mean. A parent adjudicating its own subagents is still
a model grading a model.

Neither applies to read-only work, or to ordinary code changes - those are
covered by `tdd.md` and the push gate.

## Gate A - did the write land?

1. **Count success from the write's own return value.** An inserted id, an
   affected-row count, a response body. **Never from the absence of an error.**
   An empty error is not a receipt, and a great many client libraries return
   quietly when a write is silently rejected.
2. **Read back, and count.** Re-fetch what you claim to have written, by id. The
   count must equal the intended count. A mismatch fails the run.
3. **Report failures verbatim.** Quote the error, or the two numbers that did
   not match. Never paraphrase a failure into a summary that reads like success.
4. **A uniqueness conflict is information, not an obstacle.** It means the thing
   already exists. Surface it. Never clear it by setting a force or override
   flag - those exist for a human decision, and an agent reaching for one has
   turned a question into a silent answer.
5. **Never overwrite a richer value with a thinner one**, and prefer a status
   change to a delete. Deletes destroy the record of what was there.
6. **Mark what the agent wrote**, however your system allows, so that agent
   writes can be told from yours afterwards.

## Gate B - what is allowed to reach the conclusion?

Gate A protects your data. Gate B protects your *conclusion*.

1. **Exactly one producer.** A deterministic script - not a model - writes the
   verified-findings file. Nothing else writes it.
2. **The downstream contract is narrow and explicit: synthesis reads only that
   file.** This is what makes the gate unskippable. Skip the checker and
   synthesis has no input at all, so skipping is self-defeating rather than
   merely discouraged. "Please run the checker" is a rule a model can reason its
   way past. A missing input file is not.
3. **The checker computes status. It never trusts a status the model wrote.** If
   a finding arrives already marked verified, overwrite that. The model supplies
   evidence; the script supplies verdicts. This is the most common way a gate
   quietly becomes decorative.
4. **Partition, never drop.** Three outputs: verified, unresolved, refuted. The
   last two stay on disk and get an appendix. Throwing them away destroys the
   record of what was considered and leaves you unable to answer "did you look
   at X?".
5. **Sign the pass.** Record a hash of the input and of the verified output, so
   a later reader can prove the conclusion matches the evidence it came from.
6. **Exit codes are a contract.** `0` passed - and an empty allowlist is a valid
   pass. `1` process violation, recoverable: go get the missing evidence and
   re-run. `2` hard error: the data is wrong, fix it rather than re-running.
7. **It must be able to take *verified* back.** A gate that only ever promotes
   is a progress bar, not a gate.

### What generalises, and what does not

The **harness** is reusable: evidence in, three partitioned outputs, a
signature, exit 0/1/2. The **predicate** is not - "is this finding real" means
something different in every task, and forcing two of them into one schema
produces a check that fits neither. Write the predicate concretely inside the
first task that needs it, and extract the harness on the second, not before.

## Proving a gate works

A gate that has never been broken on purpose is not known to work. It is known
to be green, which is what a gate that does nothing also produces.

Break the predicate deliberately and confirm the **specific** cases you named go
red. See `tdd.md` for the full discipline, including the ways a mutation can lie
to you. It applies to the gate exactly as it applies to the code the gate
guards - the checks are code too.

## Anti-patterns

- **Collapsing "found nothing" into "could not run".** `grep` exits 1 on
  no-match and 2 on error, so a check that treats both as success turns a broken
  scan into a passing one. `|| true` is the visible form; a plain
  `if grep -q ...; then ... fi` does the same thing and does not look like it.
  Full rule in `tdd.md`.
- **A guard that cannot see its own bug.** If the defect it was written for
  lived one hop from where the guard looks, it is coverage theatre. Delete it
  rather than keep it - a guard that catches nothing is worse than no guard,
  because it answers the question "is this covered?" with a yes.
- **Trusting a status the model wrote.** See Gate B rule 3.
- **A gate that only promotes.** No path back to unverified means no gate.
- **Restating this file inside a procedure.** Link to it in one line. Several
  hand-maintained copies of one contract is the failure that produced this
  document, and the copies do not drift visibly - they drift one clause at a
  time, and each one looks reasonable on its own.
