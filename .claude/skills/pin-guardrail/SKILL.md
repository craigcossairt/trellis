---
name: pin-guardrail
description: Pin a shell guardrail (a hook, a git hook, a checker script) with a behavioral test suite, prove the suite is real by mutating the code, and wire it into CI with its mutation ledger. Use when asked to "add tests for this hook", "pin that guard", "mutation-test this script", "this hook has no test", "wire the suite into CI", or after changing any guardrail's behaviour.
---

# Pin a guardrail with a suite you can believe

A guardrail with no behavioral test asserts nothing. CI checking that a script *parses* says
nothing about whether it *blocks*, and a guard that silently stops working is worse than no
guard, because somebody is relying on it.

The suite is the deliverable. **The mutation run is what makes the suite believable** - and most
of this file is about the ways a green suite lies to you, because every one of them has actually
happened in this repo.

## 0. Is it gated? If not, stop

Check the CI workflow actually runs the directory you are about to write into. A suite CI never
executes is decoration that reads as coverage, which is worse than no suite at all.

In this template all suites live in `bin/tests/` and `.github/workflows/hooks-ci.yml` runs each
one as its own **named step**. A named step matters: read step conclusions rather than the job
conclusion, because a job can be green while a step inside it was skipped.

## 1. Name the behaviours before you write a single case

List what the script promises: each block-or-allow decision, each exit code, each could-not-run
path, each normalisation it performs. One case per behaviour, and **write the list down first**.
That list is what you compare the mutation results against in step 4. Without it you will be
comparing against a fixture count, which is the wrong number in both directions.

## 2. Write the suite

Read an existing suite in `bin/tests/` and match its shape rather than inventing a harness.

Make it hermetic: temp trees, no network, no installed toolchain. Inject external tools as stubs
and build git fixtures directly. Anything a suite needs from the outside world is a reason it
will be skipped later, and a skipped suite is an unpinned guardrail.

End with a plain `passed: N   failed: N` line and exit non-zero on any failure.

**Fixture rules, each of which has burned this repo:**

- **Never assert on an exit code alone when the script distinguishes 1 from 2.** A helper that
  maps any non-zero onto the expected one makes every case vacuous.
- **Assert the message text wherever the message states a rule.** An error message is an
  instruction: if it tells the reader to do something the code no longer supports, no exit-code
  case can see that. This is also, repeatedly, the only thing that survives a mutation where
  another check backstops the one you are testing - see §5.
- **A skip is not a pass.** Print it out loud, say why, and never count it.
- **If the script has a two-layout dimension** - sibling versus nested, relative versus absolute,
  one worktree versus two - build a fixture for **both**. A single-layout fixture makes two
  different resolutions name the same directory and passes whatever the code does.

## 3. Predict, by name

Before mutating, write down for each mutation **which named cases** should go red. Not how many.
A mutation only has to fail the cases exercising the behaviour it broke, so the other cases
staying green is not suspicious - but a case you predicted that stays green is passing for a
reason you have not accounted for.

## 4. Mutate

**Commit first.** A harness that restores with `git checkout --` destroys any uncommitted work,
including the fix you are testing.

For every mutation the harness must:

1. **Diff the mutant against the original, and refuse to report a result if they are identical.**
   A pattern that no longer matches leaves the file unchanged, every case passes, and that
   all-green reads as "my suite does not cover this" - sending you to add a redundant case or
   rip out a guard that was working. It was never a mutation run at all.
2. **Print the diff, and read it.** "It applied" is not "it applied correctly". A replacement can
   change a different thing than you meant - an unescaped `$` in a `perl` replacement
   interpolates to empty and blanks an argument instead of changing a flag - and the file
   changed, so the identical-check passes it.
3. Run the suite and record **which** cases went red.

**Never delete or weaken a case to make a run green.**

## 5. Read the result properly - five ways a case lies

This is the part that matters, and none of it is visible from reading the suite.

**The fixture makes the attack impossible anyway.** A case asserting that a path-traversal guard
refuses `../outside` proved nothing here, because the fetch for that path failed regardless -
removing the guard still exited 2. Build the fixture so the bad thing genuinely *works* without
the guard, then assert it did not happen. If you cannot make it work, the case is documentation.

**Another check backstops the one you are testing.** Remove a guard and the exit code stays the
same because something downstream catches the same input a few lines later. The guard's real
contribution is then its *message*, and only a message assertion can go red. Record that in the
ledger rather than contriving a red - and read that ledger line before anyone "simplifies" the
guard away.

**The case went red for the previous case's reason.** Cases sharing a fixture are coupled: a
mutation that lets bad content through corrupts the fixture, and the *next* case fails for that
rather than for its own subject. An unexplained extra red is as much a signal as a missing one.
Chase it; give the case its own fixture.

**The capability probe tested the wrong direction.** A case gated on `chmod +x` sticking ran on a
filesystem where `+x` sticks and `-x` does not - so it could never go red. Probe the exact
property the case needs, in the direction it needs.

**A skipped case counted as a pass.** Say it out loud in the output, and say in the ledger which
platform actually exercises it. If a probe can *hang* rather than fail - `ln -s` on MSYS without
developer mode does exactly this - gate on the platform instead of attempting it, or one
unavailable capability wedges the whole suite.

## 6. Wire it into CI, with the ledger

Add a named step to the workflow:

```yaml
      - name: Suite - <thing>
        run: |
          # <what this pins, and why it exists at all>
          #
          # Mutation ledger, measured <date> over N cases:
          #
          #   <mutation>                          N predicted, N red
          #   <mutation>                          N predicted, N red
          #     <why the numbers differ, if they do>
          #
          bash bin/tests/test-<name>.sh
```

**The ledger is not optional.** It is the only place the figures survive, and a later reader
cannot tell a considered suite from a careless one without it.

**Record the misses, not just the wins.** The most useful line in the block is the one saying a
case proved nothing and why it is kept anyway. Every one of the five failures in §5 belongs in
the ledger of the suite it happened to.

Check in the same change: git hooks are executable (git skips a non-executable hook silently, and
on a machine with `core.fileMode=false` a `chmod` never reaches the index - use
`git update-index --chmod=+x`); no `|| true` on a `grep`, and no bare `if grep -q` where the file
list came from anywhere but a glob over the working tree. Split the three codes:

```bash
rc=0; grep -q … || rc=$?
case $rc in 0) hit;; 1) clean;; *) fail loudly;; esac
```

Unknown must never resolve to green.

## 7. Say what it does not pin

When you report, say what the suite asserts **and what it does not**. A suite that covers wiring
but not behaviour, or one whose interesting cases only run on one platform, is worth having and
worth being honest about.

And remember what mutation testing cannot do: it bounds the gap between your code and your
**tests**, never between your code and reality. It cannot surface an input you never considered
or a rule you stated and then contradicted. For anything whose failure you would care about,
follow `docs/methodology/adversarial-review.md` as well.
