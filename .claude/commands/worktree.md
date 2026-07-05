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

## Setup a Worktree

```bash
# From the repo root
git worktree add ../<repo>-worktree-<task-name> -b feature/<task-name>
```

Then open a **new agent session** in the worktree directory and work there.

## Cleanup After Merge

```bash
git worktree remove ../<repo>-worktree-<task-name>
git branch -d feature/<task-name>
git pull origin main
```

## Rules

1. **Each worktree gets its own agent session** — don't share sessions
2. **Only for truly independent work** — different files, different features
3. **Always clean up** — remove worktrees after merge to avoid stale branches
4. **Start small** — try 2 parallel sessions before scaling up
5. **Main stays clean** — the main worktree stays on the main branch

## Tips

- Name worktrees after the tracker issue ID
- Each worktree has its own dependency/build cache, so install runs once per worktree
- If you need to share changes between worktrees, commit and cherry-pick
