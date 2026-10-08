## Why

<!-- The problem, and the issue it closes. -->

## What

<!-- What changed, in a few bullets. A small diagram or pseudocode beats prose for anything structural. -->

## Verified

<!-- Each claim with its certainty-ladder level (AGENTS.md): 1 said, 2 pointed at the line,
3 walked the failure path, 4 ran a test that fails loud, 5 reproduced in the running app.
Anything short of 4 is stated as unproven. -->

## Evidence

<!--
Before/after for any visible change: a UI, a page, or output a person sees (an email,
a notification, an alert). Capture before from the untouched tree and after from the branch,
same screen, state and viewport; a short video for motion or a flow. Keep the media out of git:
attach it where the project tracks work and link it here. Missing a half? Say which and why.
Nothing visible? Write "No visible change."
-->

**Before/after:** <link> | No visible change.

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
  - anything that sends a message as the owner or the project, to anyone (chat,
    social, email to partners or vendors, internal channels too)
  - paid spend: ad campaigns, metered or paid API calls, purchases
  - production secrets and environment wiring, including config that changes which
    secret production reads
  - backfills or deletes of production data that is not user data (ledgers,
    internal tables)
  - agent config and merge gates. A revert restores the text but not what agents did
    under it in the meantime, and a weakened gate lets the next PR through on its terms:
    AGENTS.md and the files that import it, .claude/**, .cursor/**, .grok/**, .codex/**,
    .github/workflows/**, .githooks/**, bin/claim-branch.sh, bin/verify-green.sh, and
    this template (it is the merge policy)
  FILL IN: this project's own one-way paths, e.g. `migrations/**`, `functions/**`
If in doubt, it is one-way. Judge the door by what the diff DOES, not by its file names or
  the door its author picked. If the author and a reviewer disagree, it is one-way until the
  owner decides.
Two-way door: a revert fully undoes it (UI, docs, tests, most application code, and dev
  tooling that gates no merge and changes no agent behavior).
-->

**Door:** two-way | one-way (<which trigger>)
**Blast radius:** <who or what breaks if this is wrong, and how you would notice>
