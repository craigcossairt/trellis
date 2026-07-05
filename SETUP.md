# SETUP.md — Day-1 checklist

Work top to bottom. Delete this file when done (or keep it until the project has real shape).

## 1. Identity (5 min)

- [ ] `AGENTS.md` — fill every `<!-- FILL IN -->` slot: project name, owner, stage, tech stack
      table, getting-started commands.
- [ ] `AGENTS.md` § Delegation — fill in the current model names for each tier (they turn over
      every few months; the tier structure is the stable part).
- [ ] Decide the em-dash rule (keep or delete the optional content rule).

## 2. Tracker + docs (2 min)

- [ ] Point the "Active issues + priorities" line in AGENTS.md at your issue tracker (Linear
      project, GitHub Issues, etc.).
- [ ] `docs/decision-log.md` — add your first entry: the decision to start this project.

## 3. Secrets (3 min)

- [ ] `cp .env.example .env` and fill values from your password manager. `.env` is gitignored.
- [ ] If using MCP servers: `cp .mcp.json.example .mcp.json` and fill in. Also gitignored —
      commit a scrubbed version only if the whole team should share server config.

## 4. Hooks (3 min)

- [ ] `.claude/hooks/format-on-edit.sh` — check the extension → formatter map covers your stack;
      add/remove languages. It silently no-ops for missing formatters, so over-including is safe.
- [ ] `.claude/hooks/block-sensitive-files.sh` — add project-specific generated-file patterns
      (e.g. `*.g.dart` for Flutter, `*_pb2.py` for protobuf).
- [ ] Hooks run through `.claude/settings.json` with `$CLAUDE_PROJECT_DIR` paths — nothing to
      edit there unless you add hooks.

## 5. Prune (2 min)

Everything is optional. Delete what this project won't use:

- [ ] Skills you won't need (`.claude/skills/*`) — e.g. `launch-check` is for user-facing apps.
- [ ] `.cursor/` if nobody on the project uses Cursor.
- [ ] `brain/` if the project is small enough to not need a knowledge base (you can add it back
      later — it's self-contained).

## 6. Brain (optional, 10 min)

Only if you want prompt-time context injection from a local corpus. Follow `brain/README.md`:
install QMD, configure `brain/config.sh` sources, run the ingest, wire the hook. Skip on day 1;
it earns its keep once the project has real docs and history.

## 7. Sanity check

- [ ] Start an agent session in the repo root and ask: *"What are the working methodology rules
      for this project?"* — it should answer from AGENTS.md.
- [ ] Edit any source file and confirm the formatter hook ran.
- [ ] Try to edit `.env` via the agent and confirm the block hook refuses.
