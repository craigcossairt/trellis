# Coding standards

**Who reads this file: the reviewer, not the implementer.** A fresh-context review agent (or a
different model, per `docs/methodology/adversarial-review.md`) reads it in full before judging a
diff. The session that writes the code does not load it.

That split is deliberate. An agent implementing a change is already spending its context on
three jobs: exploring the code it is about to change, making the change, and debugging it until
the checks pass. Standards piled on top of that are read and then crowded out. A reviewer running
in its own context has one job, so it can hold a long list of judgment calls and apply them.
Implement to make it work; review to make it good.

## What belongs here, and what does not

Put a rule in the highest place that can hold it (the correction ladder in
`.claude/skills/learn/SKILL.md`):

1. **Impossible in code** - a type, a required parameter, a wrapper that does the right thing by
   default. Nothing to write here.
2. **A deterministic check** - a lint rule, a CI step, a ratchet at today's count. Nothing to
   write here either; the check is the rule.
3. **A judgment call no script can make** - **this file.** Layout that must survive long
   user-generated text, when an abstraction is too shallow, whether a test proves behavior or
   restates the implementation.
4. A procedure - a skill or command.
5. Something every implementing session needs before it writes a line - `AGENTS.md`, as one short
   imperative plus a pointer here for the detail.

## Standards

<!-- FILL IN: one H2 per area (UI, data access, tests, errors, naming...). For each rule, say
what to do, what goes wrong without it, and the incident or example that taught it. A rule
without its reason stops being followed the first time it is inconvenient. -->

### Tests

- A test's expected value comes from an independent source: a known-good literal, a worked
  example, or the spec. A test that recomputes the expected value the way the code does
  (a tautological test) passes by construction and can never disagree with the code.
- Test at a module's interface, not its internals. A test that reads the source file, or mocks
  the very thing under test, breaks on every refactor and catches nothing.
