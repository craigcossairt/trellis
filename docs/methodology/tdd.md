# TDD Workflow

Red-Green-Refactor for every feature and bug fix. This is the canonical methodology; the `/tdd`
slash command (Claude Code) is a thin wrapper around this file.

## Anti-patterns

- **Horizontal slicing** — do NOT write every test (happy path, edge cases, error cases) and THEN
  implement. Tests written in bulk verify *imagined* behavior — you assert the shape of things and
  the tests end up passing when behavior breaks and failing when it's fine. Work in **vertical
  slices** instead: one test → make it pass → repeat. Each test responds to what the previous
  cycle taught you.

```
WRONG (horizontal):  test1, test2, test3   then   impl1, impl2, impl3
RIGHT (vertical):    test1 → impl1   then   test2 → impl2   then   test3 → impl3
```

- **Tautological tests** — the assertion recomputes the expected value the way the code does
  (`expect(add(a, b))` against `a + b`, a hand-derived snapshot built the same way, a constant
  asserted equal to itself), so it passes by construction and can never disagree with the code.
  Expected values must come from an independent source of truth: a known-good literal, a worked
  example, the spec, or the issue's acceptance criteria.

- **Implementation-coupled tests** — mocks internal collaborators, tests private methods, or
  verifies through a side channel (querying the DB instead of using the service interface). The
  tell: the test breaks when you refactor but behavior hasn't changed.

## Steps

1. **Understand the requirement** — Read the issue or user description. Clarify ambiguity before
   writing any code. Then agree the **seams**: a seam is the public boundary you test at (service
   method, component surface, API endpoint) — tests live at seams, never against internals. Write
   down which seams are under test and confirm them with the user before writing any test; you
   can't test everything, so agreed seams put the effort on critical paths and complex logic.
   Ask: "What's the public interface, and which seams should we test?"

2. **Tracer bullet** — Write ONE failing test for the first/most-important behavior.
   - Run the test suite — confirm it FAILS (red). If it passes, it isn't testing anything new.
   - Write the minimum code to make it pass (green).
   - Run the suite — confirm green.

3. **Incremental loop** — For each remaining behavior, repeat red→green ONE test at a time:
   - Write the next failing test → confirm red
   - Add only enough code to pass it → confirm green
   - Don't anticipate future tests; keep each test on observable behavior

4. **Refactor** — Only once green. Clean up without changing behavior (extract duplication, move
   complexity behind simple interfaces). Run the suite after each step — never refactor while red.
   Then run the linter.

5. **Report** — Summarize: what was built, what tests cover, what edge cases were handled.

## Key Rules

- NEVER write implementation before its test
- ONE test at a time — never batch all tests then all code (see anti-pattern above)
- If you catch yourself writing implementation first, STOP and write the test
- One test file per source file, mirroring the source tree
- Test behavior through public interfaces, not implementation details — a test that breaks on a
  pure refactor was testing the wrong thing
- Mock external services (database, network) — never hit real infrastructure in unit tests
- For UI bugs: write a UI/widget/component test that reproduces the issue before fixing
