# CLAUDE.md

@AGENTS.md

Claude Code specifics (everything above is harness-agnostic):

- Hooks, slash commands, skills, and agents live in `.claude/` - see SETUP.md for what's wired.
- The `/tdd`, `/bug-report`, and `/worktree` commands are thin wrappers around
  `docs/methodology/` - auto-follow them without being asked to invoke them by name.
- The optional local knowledge base in `brain/` injects context via a UserPromptSubmit hook once
  initialized (see `brain/README.md`). Kill switch: `PROJECT_BRAIN_DISABLE=1`.
