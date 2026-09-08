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
# 1. is anyone already here?
bin/claim-branch.sh feature/<task-name>

# 2. if that said free, RESERVE it - this is the step that holds the branch
bin/claim-branch.sh --acquire feature/<task-name> --me <session-id> --harness claude-code
```

Exit **0** free, **1** claimed by someone else (pick another branch or
coordinate), **2** could not tell. **Exit 2 never means free.** And **a clean
fast-forward is not permission** - that is exactly what a collision looks like
from the inside, so "it merged fine" is not evidence that nobody else was there.

Run the check again before **every** push, including to a branch you created
yourself. Creating it buys you nothing once it is on the remote.
`.githooks/pre-push` runs the check for you, but only when it is installed and
not under `--no-verify` - and knowing you are about to collide before you have
built the commit is worth more than being stopped after.

Acquire from the worktree you will actually work in: `--acquire` records the
session id in that worktree's own git dir, which is how the hook tells your own
push from an intruder's.

## Setup a Worktree

```bash
# From the repo root
git worktree add ../<repo>-worktree-<task-name> -b feature/<task-name>
```

Then open a **new agent session** in the worktree directory and work there.

## Cleanup After Merge

```bash
# Release FIRST - a lease you keep blocks the branch for every other session
# until its TTL expires (4h by default), and that cost lands on someone else.
bin/claim-branch.sh --release feature/<task-name> --me <session-id>

git worktree remove ../<repo>-worktree-<task-name>
git branch -d feature/<task-name>
git pull origin main
```

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
