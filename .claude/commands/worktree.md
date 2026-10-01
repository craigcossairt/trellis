---
description: Set up parallel agent sessions on independent tasks via git worktrees. Use when asked to '/worktree', 'git worktree', 'parallel branches', 'isolated branch workspace', 'work on two things at once'.
---

# Git Worktree Workflow

Run parallel agent sessions on independent tasks using git worktrees.

## When to Use

- You have 2+ independent tasks that touch **different files**
- Tasks are on separate tracker issues
- You want to multiply throughput by running parallel sessions

## When NOT to Use

- Tasks touch the same files (merge conflicts)
- One task depends on the output of another
- Quick single-file fixes (just do them sequentially)

## Step 0: Claim the Branch

Worktrees stop two sessions sharing a **checkout**. They do nothing about two
sessions sharing a **branch**, which is the collision you actually hit once more
than one agent runs at a time - they all authenticate as the same git identity,
so nothing tells them apart.

**Checking is not claiming.** The check only reads the remote: two sessions can
both run it, both get exit 0, and both start. Acquire a lease as well.

```bash
# 1. is anyone already here? (from the repo root; this only reads the remote)
bin/claim-branch.sh feature/<task-name>

# 2. if that said free, create the worktree (see "Setup a Worktree" below)
git worktree add ../<repo>-worktree-<task-name> -b feature/<task-name>

# 3. RESERVE it, from INSIDE the new worktree - this is the step that holds the branch
cd ../<repo>-worktree-<task-name>
bin/claim-branch.sh --acquire feature/<task-name> --me <session-id> --harness claude-code
```

If step 3 exits 1, someone took the branch between your check and your acquire:
remove the worktree you just made and pick another name. Pass the branch the way
`git switch` takes it (`feature/x`, not `refs/heads/feature/x` or
`origin/feature/x`; those exit 2). `--me` and `--harness` take only
`[A-Za-z0-9._:-]`, and may not contain `RELEASE` or `CLAIM` as a whole word.

Exit **0** free, **1** claimed by someone else (pick another branch or
coordinate), **2** could not tell. **Exit 2 never means free.** And **a clean
fast-forward is not permission** - that is exactly what a collision looks like
from the inside, so "it merged fine" is not evidence that nobody else was there.

Run the check again before **every** push, including to a branch you created
yourself. Creating it buys you nothing once it is on the remote.

`.githooks/pre-push` runs the check for you, but there are three ways it does
not: the hook is not installed (`core.hooksPath` unset), the push used
`--no-verify`, or `PROJECT_ALLOW_SHARED_BRANCH=1` was set, which switches the
claim layer off for that push while leaving the green layer on. Note the last
one is a real escape hatch that prints a line saying so - so a push that scrolled
past it looks exactly like a checked one. Knowing you are about to collide
before you have built the commit is worth more than being stopped after.

Step 3 runs from inside the worktree because `--acquire` records the session id
in that worktree's own git dir, which is how the hook tells your own push from an
intruder's. A check with no `--me` honours that file only when the checkout is on
the branch being checked, so the id never vouches for anyone checking from
another checkout.

If the checkout you run `--acquire` from is not on that branch, the script still
takes the lease but prints `warning: this checkout is on '<x>', not '<branch>'`.
That is the id landing in the wrong git dir, and the worktree's push will be
refused as another session's. Re-run `--acquire` from inside the worktree:
re-acquiring your own lease is idempotent and rewrites the id there. Then delete
the stray `claim-session-id` file the warning names in the first checkout. It is
ignored while that checkout is on another branch, but if it is ever switched to
this branch it would read your live lease as its own.

## Setup a Worktree

```bash
# From the repo root, after the check in Step 0 said free
git worktree add ../<repo>-worktree-<task-name> -b feature/<task-name>
```

Then `--acquire` from inside it (Step 0, step 3), open a **new agent session** in
the worktree directory, and work there.

## Cleanup After Merge

```bash
# Release FIRST - a lease you keep blocks the branch for every other session
# until its TTL expires (4h by default), and that cost lands on someone else.
bin/claim-branch.sh --release feature/<task-name> --me <session-id>

git worktree remove ../<repo>-worktree-<task-name>
git branch -d feature/<task-name>
git pull origin main
```

Leases live on the remote as `refs/heads/claims/<branch>`, so they show up as
`claims/...` branches. That namespace is the only one hosted agent sessions can
push to, and those sessions cannot delete refs, so `--release` replaces the
lease with a RELEASED marker rather than deleting it. Every check reads a marker
as free. To clear released and expired leases out of the branch list, run
`bin/claim-branch.sh --sweep` from a session that can delete refs; it never
touches a live lease. Never name a work branch `claims` or `claims/...` - the
script refuses both.

Lease names nest like directories, so `claims/feat` and `claims/feat/x` cannot
both exist. After `--release feat` leaves its RELEASED marker, `--acquire feat/x`
exits 2 and names the clashing ref; run `--sweep`, then acquire again.

### Leases are ordinary branches, with ordinary side effects

- **Clones fetch them.** `git fetch` brings every lease down as
  `origin/claims/*`. After a sweep followed by a nested re-lease (`claims/feat`
  swept, `claims/feat/x` taken), a fetch can fail on the stale
  `origin/claims/feat`; `git remote prune origin` clears it.
- **CI runs on them.** An `on: push` workflow with no branch filter runs on
  every lease push and release. Add `branches-ignore: ['claims/**']` to it.
- **Branch rules block them.** A GitHub ruleset or branch protection that
  targets all branches (no force-push, no deletion, signed commits, PR required)
  will refuse the release (a force-update) and a takeover. Exclude `claims/**`
  from it.

### Cut-over from the old namespace

Leases used to live at `refs/claims/<branch>`. The two script versions do not
see each other's leases, in both directions:

- **New script, old lease:** every check on that branch exits 2 and prints the
  command that removes it (`git push origin :refs/claims/<branch>`). Run it once
  the lease is yours or its TTL has passed. Nothing is read as free.
- **Old script, new lease:** an old copy reads only `refs/claims/`, so it sees a
  branch leased under `refs/heads/claims/` as FREE and will take a second lease
  on it. Nothing in the new script can prevent that.

So treat the upgrade as a cut-over: before anyone acquires with the new script,
sync or rebase every worktree, clone and downstream copy of the template onto
it, and release (or let expire) every lease the old one holds.

## Rules

1. **Claim before you branch, and release when you finish** - check, `--acquire`,
   `--release`, every time (Step 0). Forgetting the release is the routine
   failure, and it blocks somebody else.
2. **Each worktree gets its own agent session** - don't share sessions
3. **Only for truly independent work** - different files, different features
4. **Always clean up** - remove worktrees after merge to avoid stale branches
5. **Start small** - try 2 parallel sessions before scaling up
6. **Main stays clean** - the main worktree stays on the main branch

## Tips

- Name worktrees after the tracker issue ID
- Each worktree has its own dependency/build cache, so install runs once per worktree
- If you need to share changes between worktrees, commit and cherry-pick
