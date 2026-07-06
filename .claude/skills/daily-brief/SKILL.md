---
name: daily-brief
description: Start-of-day ranked brief - open issues, recent commits, work in progress, and anything waiting on a human decision. Use when asked for a 'daily brief', 'morning brief', 'what should I work on today', 'start my day', 'catch me up'.
disable-model-invocation: true
---

You are producing the day's brief: a ranked answer to "what should I work on today?" grounded
in the project's actual state, not vibes.

## Gather (use what exists, skip what doesn't - never fail on a missing source)

1. **Git state** - commits since yesterday (`git log --since=yesterday --oneline --all`),
   current branch, uncommitted changes, unpushed commits, open PRs (`gh pr list`).
2. **Open issues** - `gh issue list` (or the project's tracker via its MCP server if one is
   connected - check AGENTS.md for which tracker this project uses).
3. **Project docs** - the 5 newest entries in `docs/decision-log.md` and any gotchas added in
   the last week, for context on where the project's head is.
4. **Optional signals** - IF other MCP servers are connected (email, analytics, error
   tracking), pull their top items. Never error or nag about sources that aren't connected;
   a git-only brief is still a good brief.

## Rank

Score candidate work by, in order:
1. **Unblocks something** - work that other work (or a person) is waiting on
2. **Deadline proximity** - anything dated
3. **Momentum** - in-progress work close to done beats starting something new
4. **Quick wins** - under-30-minute items worth batching

Flag separately anything that needs a HUMAN decision before an agent can act on it.

## Output format

Keep the whole brief under ~30 lines:

```
# Daily Brief - {date}

## Recommended focus (top 3)
1. {item} - {one-line why it's ranked here}
2. ...
3. ...

## Needs your decision
- {item} - {what's blocked on the human}   (omit section if empty)

## Also on the board
- {compressed list of remaining open items}

## Since yesterday
- {commits/PRs merged, one line each}
```

## Notes

- Be opinionated in the ranking - a brief that lists everything equally decides nothing.
- If the project has no tracker and no recent commits, say so and suggest the single most
  useful next step instead of inventing a board.
- This skill can be scheduled (e.g. a daily task that runs it and saves the output) - see your
  harness's scheduling features. Start by running it manually; schedule it once you trust it.
