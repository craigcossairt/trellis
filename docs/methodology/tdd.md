# TDD Workflow

Red-Green-Refactor for every feature and bug fix. This is the canonical methodology; the `/tdd`
slash command (Claude Code) is a thin wrapper around this file.

## Anti-patterns

- **Horizontal slicing** - do NOT write every test (happy path, edge cases, error cases) and THEN
  implement. Tests written in bulk verify *imagined* behavior - you assert the shape of things and
  the tests end up passing when behavior breaks and failing when it's fine. Work in **vertical
  slices** instead: one test → make it pass → repeat. Each test responds to what the previous
  cycle taught you.

```
WRONG (horizontal):  test1, test2, test3   then   impl1, impl2, impl3
RIGHT (vertical):    test1 → impl1   then   test2 → impl2   then   test3 → impl3
```

- **Tautological tests** - the assertion recomputes the expected value the way the code does
  (`expect(add(a, b))` against `a + b`, a hand-derived snapshot built the same way, a constant
  asserted equal to itself), so it passes by construction and can never disagree with the code.
  Expected values must come from an independent source of truth: a known-good literal, a worked
  example, the spec, or the issue's acceptance criteria.

- **Implementation-coupled tests** - mocks internal collaborators, tests private methods, or
  verifies through a side channel (querying the DB instead of using the service interface). The
  tell: the test breaks when you refactor but behavior hasn't changed.

## Steps

1. **Understand the requirement** - Read the issue or user description. Clarify ambiguity before
   writing any code. Then agree the **seams**: a seam is the public boundary you test at (service
   method, component surface, API endpoint) - tests live at seams, never against internals. Write
   down which seams are under test and confirm them with the user before writing any test; you
   can't test everything, so agreed seams put the effort on critical paths and complex logic.
   Ask: "What's the public interface, and which seams should we test?"

2. **Tracer bullet** - Write ONE failing test for the first/most-important behavior.
   - Run the test suite - confirm it FAILS (red). If it passes, it isn't testing anything new.
   - Write the minimum code to make it pass (green).
   - Run the suite - confirm green.

3. **Incremental loop** - For each remaining behavior, repeat red→green ONE test at a time:
   - Write the next failing test → confirm red
   - Add only enough code to pass it → confirm green
   - Don't anticipate future tests; keep each test on observable behavior

4. **Refactor** - Only once green. Clean up without changing behavior (extract duplication, move
   complexity behind simple interfaces). Run the suite after each step - never refactor while red.
   Then run the linter.

5. **Report** - Summarize: what was built, what tests cover, what edge cases were handled.

## A passing suite is not evidence - mutate it

For a suite that guards a safety control (a git hook, a permission check, an auth rule, RLS),
a green run only proves the tests didn't complain - not that they *can* complain. A case that
looks right can assert nothing: a helper that maps any failure onto the expected one, a regex
that still matches with the fix reverted, an assertion built the same way the code is.

Before trusting such a suite, break the thing under test on purpose - revert the fix, flip the
condition, disable the hook - and confirm the *specific* cases fail. Then restore it. State the
mutation and its result when reporting: "reverting X fails N cases" is the claim that makes a
suite trustworthy. (One production day surfaced three separate vacuous-case sets in a single
hook suite; reading the tests had caught none of them, the mutations caught all three.)

This is the suite-level form of step 2's "confirm it FAILS (red)" - a test you have never seen
fail has never been tested. In the language of the certainty ladder in `AGENTS.md`, a green run
is level 1 and a mutated run is level 4.

### Four ways a mutation still lies to you

- **Name the cases that must fail before you run the mutation, then compare.** A red mutation
  vindicates the *case*, not each assertion inside it, and it only has to fail the cases that
  exercise the behavior you broke - so a raw count on its own proves nothing in either
  direction. Predict the set, then read *which* cases went red. One suite had three fixtures
  for a single regex, all three of which should have failed; two contained characters that
  failed that regex before the code under test ever ran, so breaking the code failed 3 cases
  and read as covered. Corrected fixtures made the same mutation fail 6. When a case you
  predicted stays green, it is passing for a reason you have not accounted for.

- **Mutate against the actual historical bug, not a synthetic one.** A CI grep guard written
  for a specific defect passed its synthetic mutation and still could not see the real one,
  because the real one lived a hop away (in a variable assignment) from the site a grep can
  reach. A guard that cannot see the bug it is named after reads as coverage while catching
  nothing. Delete it rather than keep it.

- **A guard must distinguish "clean" from "failed to run".** `grep` exits 1 on no-match but 2
  on error, so `|| true` collapses a broken scan into a passing one. Unknown must never resolve
  to green, and that applies to the checks themselves, not only to the code they check.
  The inverse is just as real and easier to miss: a check that treats *zero results* as "the
  scan must be broken" will block everything the day an empty result becomes legitimate.
  Separate *could not run* (missing input, missing required file) from *ran and found nothing*
  (fatal vs clean). Guarding the extractor is the unit suite's job, not an arbitrary
  "at least one result" floor in the checker.

- **A check on LLM behavior needs a fixture where the misbehavior is the naively-faithful
  output.** One containment check stayed green with its containment rules stripped from the
  prompt, because the surrounding schema steered the model away from the bad output anyway -
  the check could not tell the instruction from the schema. It only went red once the fixture
  made the bad output the *semantically correct* answer to the question asked. If the guarded
  misbehavior is not the natural output on your fixture, a passing check proves the fixture,
  not the guard.

## Key Rules

- NEVER write implementation before its test
- ONE test at a time - never batch all tests then all code (see anti-pattern above)
- If you catch yourself writing implementation first, STOP and write the test
- One test file per source file, mirroring the source tree
- Test behavior through public interfaces, not implementation details - a test that breaks on a
  pure refactor was testing the wrong thing
- Mock external services (database, network) - never hit real infrastructure in unit tests
- For UI bugs: write a UI/widget/component test that reproduces the issue before fixing
