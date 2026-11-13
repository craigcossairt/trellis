# SETUP.md - Day-1 checklist

This page gets your project set up. Work top to bottom. The core steps (1 to 5 and the check
in 9) take about 15 minutes. Steps 6 to 8 are three decisions, a few minutes each. Make them
rather than skip them: each one is cheap today and easy to forget later.

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
- [ ] Do not run your AI tool's "write my rules file" command over this (`/init` in Claude
      Code). `AGENTS.md` already is that file. Such a command fills it with things the AI can
      read from the code anyway, and every line in it is loaded into every session, so it should
      hold only what the code cannot say.
- [ ] In the same file, find the **Delegation** section and fill in a model family for each
      tier - the alias your AI tool takes (for example `haiku`, `sonnet`, `opus`), not a
      version number, so the table does not go stale when a new model ships. If you are not
      sure, ask your AI: *"which model families can my tool dispatch to?"*
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
- [ ] Never paste a key into a settings file such as `.claude/settings.json`, and that includes
      its `env` block. That file is committed with your project. Even a settings file git
      ignores is one your AI opens and reads, and whatever it reads is copied into the saved
      record of the session. Keys go in `.env` or in your password manager.
- [ ] Only if you use MCP servers (extensions that give your AI access to outside tools like a
      database or your issue tracker): make a copy of `.mcp.json.example` named `.mcp.json` and
      fill it in. Also ignored by git, so it is set up once per computer. If you do not know
      what this means, skip it - you can come back when you need one.

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
      To bypass test verification once, put `PROJECT_SKIP_VERIFY=1` in front
      of your push command. The branch-claim check still runs.

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
- [ ] **The shared-checkout check** (`bin/check-main-checkouts.sh`) and the optional heredoc
      warning (`.claude/hooks/heredoc-backslash-warn.mjs`) if you will never run parallel
      sessions on one machine or wire the warning. Both do nothing until you opt in
      (`.claude/hooks/README.md` § Optional hooks). Delete each with its suite in `bin/tests/`
      or `.claude/hooks/tests/`; hooks CI skips a suite whose subject file is gone.
- [ ] **The repository-settings check** (`bin/check-repo-settings.sh`, its suite
      `bin/tests/test-check-repo-settings.sh`, and `.github/dependabot.yml`) if this project
      will never live on GitHub. Step 8 is where it gets used.
- [ ] **`brain/`**, but not on a guess: step 7 decides it from what your project has. If the
      answer there is "delete", remove `brain/` and `bin/tests/test-brain-refresh.sh` together.
- [ ] **`examples/`** once your own `AGENTS.md` is filled in. It is a worked sample of a
      finished one, and nothing else refers to it.

## 6. Choose your outside tools (5 min)

This template works on its own. A few outside tools are still worth choosing on purpose, because
the other way to meet them is by accident, at a bad moment. You do not have to read the whole
catalogue: `docs/recommended-tooling.md` opens with a **Start here** table, one row per
situation. Find the rows that describe you.

- [ ] Decide these three today, even where the answer is the free default:
      - **Where your secrets live.** A password manager. This is the one that cannot wait.
      - **Where your to-do list lives.** GitHub Issues is free and already attached to your
        repo. Linear is the pick once you are ranking a long backlog. Whichever you choose is
        what step 2 points at.
      - **Whether to add a skill pack.** Matt Pocock's skills are the pack the tooling page
        recommends: they make your AI question the plan before it builds anything. One of them
        overlaps this template's own test-first workflow, and the tooling page says how to
        settle which of the two is in charge.
- [ ] If you run more than one AI session at a time, or more than one AI tool, read the
      **T3 Code** entry. It puts all of them in one window.
- [ ] For every other row that fits you, the table says *when* to add it. Most wait until real
      people use what you built. Note the "later" ones in `docs/decision-log.md` with what
      would make you add them, so the reminder is somewhere you will see it.
- [ ] Before installing any skill pack, read its line under **Overlaps and collisions** on that
      page. Some popular packs install skills under names this template already uses.
- [ ] Write what you chose into `AGENTS.md` (the Tech Stack table and the issue-tracker line).
      Your AI then uses the tools you picked instead of guessing.

## 7. Project memory: decide it now (2 min to decide, 10 to set up)

`brain/` is a search index over your own docs and history that lives on your computer. Once it
is on, background that matches what you are asking about is added to your prompt without you
doing anything. Whether to set it up today depends on what your project has, so decide from
that rather than from how busy you feel.

- [ ] **Set it up now** if any of these is true:
      - The project already has about 15 documents of your own (specs, notes, decisions - not
        the files this template shipped), or a few weeks of commit history.
      - You are bringing material with you: research, a product spec, meeting notes, an export
        from another tool. Put it under `docs/` first.
      - You plan to write things down as you build (requirements, decisions, research) and
        expect the project to run for months. An index that is already running picks those up
        as they appear. One you meant to set up later usually never gets set up.

      Then follow `brain/README.md`. It installs two programs (bun and QMD) and takes three
      commands.
- [ ] **Leave it for later** if this is a new project with nothing written down and no plan to
      write much. Add a line to `docs/decision-log.md` saying when you will come back ("set up
      `brain/` when `docs/` has 15 files of mine"), because nothing else will remind you.
- [ ] **Delete it** if you already use another memory tool, or neither case above will ever
      apply. Running two memories is worse than running one.
- [ ] One limit to know before you choose: the automatic part works in Claude Code, Grok Build
      and Codex. In Cursor, Gemini CLI and Copilot the index still builds and you (or your AI)
      search it by hand. `docs/harness-support.md` has the table.
- [ ] **If you set it up, schedule its refresh.** The index only knows what it was last fed, so
      one built today and never refreshed is answering from today's project in three months.
      The whole job is one command, `bash brain/scripts/refresh.sh`, run once a day by your
      computer's own scheduler. `brain/README.md` § Keeping it current has lines to paste for
      macOS, Linux and Windows, and a check that the scheduled run will work before you rely
      on it. It has to run on your computer: the index is not in git, so a job running in the
      cloud has nothing to refresh. A scheduled run that fails leaves a note, and your next AI
      session shows it at the top. A schedule that never starts leaves no note, so that case
      shows up as a "stale" line once the index is a week old. Both lines need a tool that
      runs this template's session-start hook: Claude Code, Cursor, Grok Build or Codex.

## 8. Your GitHub repository's settings (3 min)

Some protection is a switch in your repository's settings on GitHub rather than a file in this
folder, so copying the template did not bring it with you. One command reads those switches and
tells you which are off. It only reads. It changes nothing.

- [ ] Run `bash bin/check-repo-settings.sh`. It needs the GitHub command-line tool (`gh`),
      signed in as someone who can administer the repository. It checks the repository this
      folder pushes to: its `origin` remote, which has to be on github.com. What it looks at:
      - **Dependabot alerts and security updates.** GitHub tells you when something your
        project depends on has a known security hole, and opens the fix for you. GitHub pauses
        those fixes when its pull requests sit untouched for 90 days, and the script reports
        paused as off.
      - **Secret scanning and push protection.** GitHub refuses a push that contains something
        shaped like a real key. This is the net under step 3.
      - **Protection on your main branch.** A rule that stops anyone, an AI included, from
        force-pushing over it or deleting it. Anyone on the rule's bypass list can still do
        both, unless their entry is limited to pull requests, so leave that list empty. The
        script does not count a rule that somebody can push past.
      - **Smaller ones:** merged branches delete themselves, automated workflows start with
        read-only access, and (public repositories) people can report a security problem to
        you privately.
- [ ] For each line marked `OFF`, the script prints the command or the settings page that turns
      it on. Decide each one separately. Nothing here is required, and all of it can be undone.
      If you are not sure, turn them all on: none of them costs money, and each one only stops
      or reports something you would want stopped or reported. One has a side effect worth
      knowing. With read-only access as the default, a workflow that writes (commits, labels,
      releases) needs a `permissions:` block of its own.
- [ ] Run the script again when you are done. A setting is on when the script says so, not
      when the command that changed it returned without an error.
- [ ] Read the other marks correctly. `SKIP` means the setting does not apply to this
      repository or is not offered on your GitHub plan. `UNKNOWN` means the script could not
      read it, which is not the same as on. Its line says why. The usual fixes are
      `gh auth login`, or asking whoever administers the repository to run the check.
- [ ] Open `.github/dependabot.yml` and add an entry for the language your project is written
      in. As shipped it watches only the GitHub Actions this template's own checks use, and it
      knows nothing about your app's packages until you tell it. The comments at the top of the
      file show how. Copy the whole shipped entry: GitHub requires a `directory` and a
      `schedule` on each one, and the script reports the file as off when an entry is
      missing either. Two things come with keeping the file. GitHub opens a pull request, at
      most weekly, when one of those actions has a newer release. And that pull request edits
      `.github/workflows/hooks-ci.yml`, a file the template also updates, so a later
      `/trellis-sync` shows it as changed on both sides and asks which version to keep. Delete
      the file if you want neither.

## 9. Check that it worked (5 min)

Do not skip this. A safety rail that silently does nothing looks exactly like one that is
working. The only way to tell them apart is to try to break something on purpose.

- [ ] Start an AI session in this folder and ask: *"What are the working methodology rules for
      this project?"* It should answer from `AGENTS.md`. If it does not, your AI tool is not
      reading the file, and nothing else on this page is doing anything either.
- [ ] Run `bash bin/check-instruction-budgets.sh`. Filling in `AGENTS.md` made it longer, and
      one tool (Codex) drops whatever is past its size limit without telling you. If the check
      says the file is over, move a long explanation out to `docs/` and leave a one-line
      pointer to it.
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
- [ ] If you set up `brain/`: run `bash brain/scripts/refresh.sh` once by hand. It should end
      with `brain refresh: done.` Do this before trusting the schedule to run it.

## One last thing

If this template saved you time, please star it on GitHub:
https://github.com/craigcossairt/trellis

Stars are how other people find it. That is the whole ask.
