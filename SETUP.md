# SETUP.md - Day-1 checklist

Work top to bottom. Delete this file when done (or keep it until the project has real shape).

> **Shortcut:** open your AI coding tool and say *"walk me through SETUP.md"* - it will ask you
> the fill-in questions conversationally and make the edits for you. Recommended if you're not
> used to editing config files by hand.

## 1. Identity (5 min)

- [ ] `AGENTS.md` - fill every `<!-- FILL IN -->` slot: project name, owner, stage, tech stack
      table, getting-started commands.
- [ ] `AGENTS.md` § Delegation - fill in the current model names for each tier (they turn over
      every few months; the tier structure is the stable part).
- [ ] Decide the em-dash rule (keep or delete the optional content rule).
- [ ] `docs/about-me.md` - fill in your background, technical level, and working style. Five
      minutes here upgrades every piece of advice agents give you.

## 2. Tracker + docs (2 min)

- [ ] Point the "Active issues + priorities" line in AGENTS.md at your issue tracker (Linear
      project, GitHub Issues, etc.).
- [ ] `docs/decision-log.md` - add your first entry: the decision to start this project.

## 3. Secrets (3 min)

- [ ] `cp .env.example .env` and fill values from your password manager. `.env` is gitignored.
- [ ] If using MCP servers: `cp .mcp.json.example .mcp.json` and fill in. Also gitignored -
      commit a scrubbed version only if the whole team should share server config.

## 4. Hooks (3 min)

- [ ] `.claude/hooks/format-on-edit.sh` - check the extension → formatter map covers your stack;
      add/remove languages. It silently no-ops for missing formatters, so over-including is safe.
- [ ] `.claude/hooks/block-sensitive-files.sh` - add project-specific generated-file patterns
      (e.g. `*.g.dart` for Flutter, `*_pb2.py` for protobuf).
- [ ] Hooks run through `.claude/settings.json` with `$CLAUDE_PROJECT_DIR` paths - nothing to
      edit there unless you add hooks.
- [ ] Optional push gate: fill in `GREEN_COMMANDS` in `bin/verify-green.sh` (your lint/test
      commands). Once non-empty, `git push` refuses any commit whose checks were never seen
      passing - run `bash bin/verify-green.sh` before pushing to record the proof. The wiring
      (`core.hooksPath=.githooks`) self-installs at session start; bypass with
      `PROJECT_SKIP_VERIFY=1` for docs-only pushes. Leave the array empty to keep the gate off.

## 5. Prune (2 min)

Everything is optional. Delete what this project won't use:

- [ ] Skills you won't need (`.claude/skills/*`) - e.g. `launch-check` is for user-facing apps.
- [ ] Harness adapters nobody on the project uses: `.cursor/`, `.grok/`, `GEMINI.md`,
      `.github/copilot-instructions.md`. (If you keep `.cursor/` or `.grok/`, keep
      `bin/run-claude-hook.sh` too - it's their shared hook adapter.)
- [ ] The push gate (`.githooks/`, `bin/verify-green.sh`, `bin/install-git-hooks.sh`) if you
      never want push-time verification. It's inert until configured, so keeping it costs
      nothing.
- [ ] `brain/` if the project is small enough to not need a knowledge base (you can add it back
      later - it's self-contained).
- [ ] `examples/` once you've filled in your own AGENTS.md (it's a reference sample, nothing
      points to it).

## 6. Third-party tooling (optional, 5 min)

- [ ] Skim `docs/recommended-tooling.md` - curated third-party skill packs (engineering
      discipline, frontend design, persona commands) with install commands and collision
      warnings. All user-level; install once per machine.

## 7. Brain (optional, 10 min)

Only if you want prompt-time context injection from a local corpus. Follow `brain/README.md`:
install QMD, configure `brain/config.sh` sources, run the ingest, wire the hook. Skip on day 1.
Rule of thumb: enable it once the project has roughly 15-20 real docs/decisions or a few weeks
of commit history - before that there's nothing worth searching.

## 8. Sanity check

- [ ] Start an agent session in the repo root and ask: *"What are the working methodology rules
      for this project?"* - it should answer from AGENTS.md.
- [ ] Edit any source file and confirm the formatter hook ran.
- [ ] Try to edit `.env` via the agent and confirm the block hook refuses. A guardrail that
      no-ops looks identical to one that passes - only a deliberate violation proves it's alive.
- [ ] If you configured the push gate: commit a trivial change and `git push` WITHOUT running
      `bin/verify-green.sh` first - confirm the push is blocked, then verify and push for real.
