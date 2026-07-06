# AI Session Management

Habits for keeping agent sessions effective. Context quality degrades well before the context
window is technically full - every turn is a branching point. These are the defaults; AGENTS.md
carries the summary version.

- **Prefer rewinding over mid-session correction.** When you read files, try an approach, and it
  flops - jump back to just after the reads and re-prompt with what you learned. Don't pile
  corrections on top of a bad chain; it multiplies context rot. (Claude Code: `/rewind` or
  esc esc. Other tools: start a fresh session and paste the learnings.)

- **New task = new session.** Pivoting from debugging to an unrelated task is a fresh session,
  not a continue. Exception: closely related follow-ons (writing docs for the feature you just
  shipped).

- **Compact with direction.** When a long session approaches its context limit, summarize with an
  explicit instruction ("keep the refactor context, drop the test debugging"). Bad compactions
  happen when the tool can't predict the next direction.

- **Explicit subagent delegation for big-output tasks.** When a task produces large intermediate
  output you won't need again (security review, exhaustive searches, bulk file scans), route it
  through a subagent so only the final report hits main context. Mental test: "Do I need the tool
  output or just the conclusion?"

- **"Summarize from here" before ending.** When ending a session mid-stream, ask the agent to
  summarize learnings as a handoff message to the next session. Better than writing the brief
  from scratch.
