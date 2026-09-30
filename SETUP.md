# SETUP.md - Day-1 checklist

This page gets your project set up. Work top to bottom. The core steps take about 15 minutes.

## Two ways to do this

**Let your AI do it.** Open your AI coding tool in this folder and say *"walk me through
SETUP.md"* - or use `/setup` in Claude Code or `$setup` in Codex. It asks you each question in plain conversation,
makes the edits for you, and shows you every change before saving it. You will not have to edit
a config file by hand. It starts by asking how much you have built before, and explains more or
less depending on your answer. This is the recommended path if you are new to this.

**Do it yourself.** Follow the checkboxes below. A few steps use a terminal (the window where
you type commands instead of clicking). Each one says exactly what to type.

Either way, nothing here is permanent. Every piece of this template is optional and deletable.

Delete this file when you are done, or keep it until the project has real shape.

---

## 1. Tell the AI about your project (5 min)

Right now your AI knows nothing about what you are building. This step fixes that. What you fill
in here is read at the start of every session, by every AI tool you use, so you never have to
re-explain your project.

- [ ] Open `AGENTS.md` and fill in every slot marked `<!-- FILL IN -->`: project name, what it
      does, who owns it, what stage it is at, and your tech stack. If you do not know your stack
      yet, write what you are leaning toward. You can fix it later.
- [ ] In the same file, find the **Delegation** section and fill in a model name for each tier.
      AI models get replaced every few months, so this is a note to yourself, not a setting.
      If you are not sure, ask your AI: *"what are the current models for each tier?"*
- [ ] Decide whether to keep the em dash rule. Em dashes are the long dashes that AI writing
      uses constantly, so banning them is a quick way to make your public writing read as human.
      Keep the rule or delete it.
- [ ] Open `docs/about-me.md` and fill it in, especially **Technical level**. This is the
      highest-value five minutes on this page. An AI that knows you have never used git explains
      things completely differently from one that assumes you have. Write it as plain sentences,
      not a rating: *"I can read code but I have never used branches"* tells it far more than
      *"beginner"*. Change this file whenever your comfort level changes.

## 2. Point at your to-do list (2 min)

Your AI should never guess what you are working on next. It should look it up.

- [ ] In `AGENTS.md`, find the "Active issues + priorities" line and point it at wherever you
      track work: a GitHub Issues page, a Linear project, a Trello board, any URL. If you do not
      have one yet, GitHub Issues is free and already attached to your repo.
- [ ] Open `docs/decision-log.md` and add your first entry: the decision to start this project,
      and why. This file becomes the answer to *"why on earth did I do it that way?"* six months
      from now.

## 3. Keep your passwords and keys out of git (3 min)

A secret is any password, API key, or token. The rule is that they never go in git, because
anything committed to git is very hard to truly delete.

- [ ] Make a copy of `.env.example` and name the copy `.env`, then fill in your values.
      In a terminal that is `cp .env.example .env`. The `.env` file is already set up to be
      ignored by git, so it will not be committed by accident.
- [ ] Only if you use MCP servers (extensions that give your AI access to outside tools like a
      database or your issue tracker): make a copy of `.mcp.json.example` named `.mcp.json` and
      fill it in. Also ignored by git. If you do not know what this means, skip it - you can
      come back when you need one.

## 4. Turn on the safety rails (3 min)

A **hook** is a small script that runs automatically at a specific moment, without anyone asking
it to. This template ships four: one tidies your code after every edit, one refuses to let the
AI touch your secrets, one shows you where you left off at the start of a session, and one feeds
relevant project background into your prompts (that last one stays off until you set up `brain/`
in step 7). Choose your tool's adapter and activate it before checking that the hooks
fit your project. `docs/harness-support.md` lists the coverage and limits.

- [ ] **Codex:** install Python 3.10+ and Bash (Git for Windows on Windows).
      Confirm `python3 --version` on macOS/Linux or `python --version` on Windows.
      Trust this project in Codex, then use `/hooks` in Codex CLI to review and trust
      `.codex/hooks.json`. New or changed definitions need review again. See
      `.codex/README.md` for Windows paths and the `TRELLIS_BASH` override.
- [ ] **Other tools:** Claude uses `.claude/settings.json`; Cursor requires a
      trusted workspace; Grok Build requires `/hooks-trust`. Gemini CLI and
      Copilot have no in-session hook adapter here; the Git push gate still works.

- [ ] Open `.claude/hooks/format-on-edit.sh`. This one tidies the layout of your code every time
      a file is saved. Check that the list covers the languages you are using, and add yours if
      it is missing. If the tidying tool for a language is not installed, the hook quietly does
      nothing, so listing extra languages is harmless.
- [ ] Open `.claude/hooks/block-sensitive-files.sh`. This one refuses to let the AI edit your
      secrets, your lock files, and any file that is generated by a tool rather than written by
      a person. Add patterns for your own generated files if you have them (for example
      `*.g.dart`, or `*_pb2.py`).
- [ ] Keep the canonical scripts in `.claude/hooks/` for every tool using hooks.
      The adapters translate events; they do not duplicate the policy.
- [ ] **Install the Git hook in every clone**, regardless of your coding tool:
      `bash bin/install-git-hooks.sh`. Check `git config --get core.hooksPath`:
      it must resolve to this project's `.githooks/`. If the installer reports an
      existing hook manager, follow its message and integrate the hooks before
      claiming the gate is active. This step does not depend on a session hook.
      From Windows PowerShell, invoke Bash as
      `& 'C:\Program Files\Git\bin\bash.exe' bin/install-git-hooks.sh`.
- [ ] **Optional - the push gate.** This one refuses to let you push code whose tests were never
      seen passing, which is the single most useful guardrail here once you have tests. To turn
      it on, open `bin/verify-green.sh` and fill in `GREEN_COMMANDS` with the commands that
      check your project (your linter, your tests). Review and stage the intended
      changes, then run `bash bin/verify-green.sh` before pushing. Verification
      refuses unstaged tracked edits and non-ignored untracked files because
      they would let tests see content absent from the commit. Ignored dependency
      and build directories are allowed. Leave the list empty and the
      gate stays off, which is the right choice until you have tests worth gating on.
      Verification also refuses Git's `assume-unchanged` and `skip-worktree`
      flags because they hide edits; use a full checkout rather than a sparse
      checkout for this gate. It never clears those flags for you.
      To push without it once, put `PROJECT_SKIP_VERIFY=1` in front of your push command.

## 5. Delete what you will not use (2 min)

Everything here is optional. A smaller template you understand beats a larger one you do not.

**Two things to keep even though you will not touch them:** `.trellis/` and
`bin/trellis-sync.sh`. The first records what the template shipped when you copied it, and the
second is what later tells a file you edited on purpose from one the template changed. Delete
either and there is no way to take a future improvement without hand-diffing. One rule comes with
them: never run `bin/trellis-manifest.sh --write` in your project. That regenerates the record
from *your* tree, which makes your own edits look like template files - it now refuses to run
here, and this is why. That refusal is a backstop, not a fence. It compares your `origin` to the
upstream recorded in `.trellis/source` and refuses unless both the host is `github.com` and the
owner/repo matches - so a non-GitHub origin is refused too, and `--force` is the only way past
either. The one case it cannot judge is a project with **no** `origin` set yet, which it allows,
because a repo with no remote is indistinguishable from the template's own checkout. The rule is
what protects you; the check only catches the common case.

- [ ] **Skills you do not need** (`.claude/skills/*`). A skill is a saved procedure your AI can
      follow on request. `launch-check`, for example, only makes sense for an app real people
      will use. If you delete a skill, delete its matching file in `.cursor/skills/<name>/` in
      the same commit, and its `.agents/skills/<name>/` router if that adapter remains.
      Those files are pointers, and the automated checks fail if a pointer aims
      at something that no longer exists.
- [ ] **Adapters for AI tools nobody here uses**: `.cursor/` (Cursor), `.grok/` (Grok Build),
      `.agents/` (Codex skills), `.codex/` (Codex hooks),
      `GEMINI.md` (Gemini CLI), `.github/copilot-instructions.md` (GitHub Copilot). If you keep
      `.cursor/` or `.grok/`, also keep `bin/run-claude-hook.sh`, which is how those two run the
      same safety rails.
- [ ] **The push gate** (`.githooks/`, `bin/verify-green.sh`, `bin/install-git-hooks.sh`) if you
      never want push-time checks. It does nothing until you configure it, so keeping it costs
      you nothing.
- [ ] **`brain/`** if your project is too small to need a searchable memory. You can add it back
      later; it is self-contained.
- [ ] **`examples/`** once your own `AGENTS.md` is filled in. It is a worked sample of a
      finished one, and nothing else refers to it.

## 6. Outside tools (optional, 5 min)

- [ ] Skim `docs/recommended-tooling.md`. It covers add-on skill packs and the services worth
      paying for, with collision warnings where one would tread on something already in here.
      Read the warnings before installing anything: some popular packs install skills under
      names this template already uses.

## 7. Project memory (optional, 10 min)

This sets up a local search index over your own docs and history, so relevant background gets
pulled into your prompts automatically. It is genuinely useful and genuinely not a day-1 task.

- [ ] Skip this for now. Come back when the project has roughly 15 to 20 real documents and
      decisions, or a few weeks of history. Before that there is nothing worth searching.
      When you are ready, follow `brain/README.md`.

## 8. Check that it worked (5 min)

Do not skip this. A safety rail that silently does nothing looks exactly like one that is
working. The only way to tell them apart is to try to break something on purpose.

- [ ] Start an AI session in this folder and ask: *"What are the working methodology rules for
      this project?"* It should answer from `AGENTS.md`. If it does not, your AI tool is not
      reading the file, and nothing else on this page is doing anything either.
- [ ] For a tool with hooks, edit a code file whose formatter is installed and
      confirm the formatting hook ran. Codex's edit adapter covers `apply_patch`;
      shell writes are outside its file-path check.
- [ ] In a disposable project with a dummy `.env`, request an edit and confirm
      the hook reports the blocked call. An agent declining in prose does not
      prove the hook ran. Do not use a real credentials file for this check.
- [ ] For Codex, run `python3 bin/validate-codex.py` and
      `python3 bin/tests/test_codex_hooks.py` (use `python` on Windows). The former
      checks static wiring; the latter tests payload handling in fixtures. Neither
      proves an interactive session has trusted the project and hooks.
- [ ] If you turned on the push gate: make a trivial change, commit it, and push WITHOUT running
      `bash bin/verify-green.sh` first. The push should be refused. Then run the check and push
      again for real.
