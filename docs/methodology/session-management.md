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

- **Measure what loads before your first prompt.** Rule files, memory, every installed skill's
  description and every connected tool's definition are in the window before you type anything,
  in every session. Most tools can show the breakdown (Claude Code: `/context`). Look once after
  setup and again whenever you install a pack. What it shows is spent before work starts, in
  every session, and whatever serves things this project never uses is waste. Turn off the plugins
  and MCP servers a project does not need in that project's own settings rather than globally,
  so your other projects keep them.

- **Keep a long run's task list in a file.** For work that spans many steps or may outlive a
  compaction, keep the checklist in a scratch file and tick each item as it lands. A compaction
  summarizes the plan away and the file keeps it, so the file is where the owner looks to see
  what is done and what is left. Commit it only if it is itself a deliverable.
