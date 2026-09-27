## Why

<!-- The problem, and the issue it closes. -->

## What

<!-- What changed, in a few bullets. A small diagram or pseudocode beats prose for anything structural. -->

## Verified

<!-- Each claim with its certainty-ladder level (AGENTS.md): 1 said, 2 pointed at the line,
3 walked the failure path, 4 ran a test that fails loud, 5 reproduced in the running app.
Anything short of 4 is stated as unproven. -->

## Merge danger

<!--
How carefully a human needs to read this PR. Pick one door and name the blast radius.
Reviewers read one-way doors closely and skim two-way ones, so an understated door is how a
risky change gets a skim.

One-way door: a revert does NOT undo it. It is one-way if the diff touches ANY of:
  - schema or data migrations            (they outlive a revert)
  - code that deploys to production on merge, and the scripts or CI jobs that do the
    deploying (a bad edit to the deploy machinery ships everything at merge time)
  - anything that sends email, push or SMS to real users
  - payments, billing or entitlements
  - auth, permissions, row-level security, or secrets handling
  - deleting or rewriting user data
  - a release tag, store listing, or production build configuration
  FILL IN: this project's own one-way paths, e.g. `migrations/**`, `functions/**`
Two-way door: a revert fully undoes it (UI, docs, tests, tooling, most application code).
-->

**Door:** two-way | one-way (<which trigger>)
**Blast radius:** <who or what breaks if this is wrong, and how you would notice>
