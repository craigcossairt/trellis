# Recommended third-party tooling

Optional, battle-tested third-party skill packs and tools worth using alongside this template.
Most skill packs are **user-level installs** (they live in `~/.claude`, shared across all your
projects) - install those once per machine, not per project. Two are not: pstack is a plugin
for Cursor and Claude Code, and Impeccable installs per project. Each entry states its own scope. They are
referenced here rather than vendored so they update from source and their licensing stays clean.

## Start here

Nobody needs everything on this page. Find the rows that describe you and leave the rest. If
your AI is walking you through setup, it goes through this table with you.

| If this is you | Pick | When |
|---|---|---|
| Anyone | A password manager (Bitwarden or 1Password) | Today. Real keys live there, never in the repo |
| Anyone | GitHub Issues as your to-do list | Today. Free, and already attached to your repo |
| You want your AI to question your plan before it builds | [Matt Pocock's skills](#matt-pococks-skills---engineering-discipline) | Today, if that is you. Read its three notes first |
| You are ranking a long backlog, or planning in cycles | Linear | When GitHub Issues stops being enough |
| You run several AI sessions at once, use more than one AI tool, or want to check on a run from your phone | [T3 Code](#t3-code---every-agent-session-in-one-window) | The first time one terminal window is not enough |
| You are building screens people will look at | [Impeccable](#impeccable---frontend-design-quality) | When the first screen exists |
| You merge code your AI wrote and cannot review all of it yourself | CodeRabbit | From your first pull request |
| Your project stores user data and you have not picked a backend | Supabase | When you start building it |
| You have a web app to show someone | Vercel | When there is something to show |
| Real people are about to use it | Sentry and UptimeRobot | Launch week, not before |
| Your documents are Word files or PDFs, and you turned on `brain/` | [anydoc](#anydoc---documents-into-markdown-so-your-knowledge-base-can-read-them) | The day you turn `brain/` on |
| You already run skill packs of your own | [Overlaps and collisions](#overlaps-and-collisions) | Before you install anything here |

The services without a link are in the [Services & integrations](#services--integrations) table,
with what each costs and when it earns its place.

**Read [Overlaps and collisions](#overlaps-and-collisions) before you install anything.** Skill
packs install into a shared namespace. Some of the packs below ship a skill under a name this
template already uses, and one of them edits files this template owns.

## Matt Pocock's skills - engineering discipline

Twenty-seven skills that make the agent slow down before it builds. It grills you on the plan
(`grill-me`, `grill-with-docs`), runs a real debugging loop (`diagnosing-bugs`), turns a
conversation into a spec and a spec into tickets (`to-spec`, `to-tickets`), keeps a glossary of
your project's words (`domain-modeling`), and reviews a change against your own standards
(`code-review`). Start with the grilling skills: they are the ones people install it for.

Where your tool has plugins, install it as one, so it updates itself:

```bash
# Claude Code
claude plugin install mattpocock-skills@claude-plugins-official

# Codex
codex plugin marketplace add mattpocock/skills
codex plugin add mattpocock-skills@mattpocock

# Cursor and others: copies editable files into the project, and lets you pick skills
npx skills@latest add mattpocock/skills
```

Use one route per tool; his README warns that using both gives you every skill twice. Then run
`/setup-matt-pocock-skills` once in the project. His README has the lines for Copilot and
Gemini CLI.

**Three things to know with this template.** All three were read from the skill text at version
1.3.1 on 2026-11-13, not found by running the skills.

1. **Two test-first workflows.** His `tdd` and `implement` cover the same ground as this
   template's `/tdd` and `docs/methodology/tdd.md`. Pick one authority. `AGENTS.md` here
   already names the template's; keep that line, or delete the template's version and the
   line with it. A plugin arrives whole, so leaving `tdd` out is only possible on the
   `npx skills` route.
2. **Its setup skill writes into your repo.** `/setup-matt-pocock-skills` adds an
   `## Agent skills` block to `CLAUDE.md` when that file exists (and to `AGENTS.md` only when
   it does not), writes `docs/agents/*.md`, and can create issue labels on GitHub. This
   template's `CLAUDE.md` is a short pointer that only Claude Code reads, so the block lands
   where your other tools never see it. Move it into `AGENTS.md` afterwards.
3. **Names changed, so older notes mislead.** `to-prd` is now `to-spec`, `to-issues` became
   `to-tickets`, `diagnose` is `diagnosing-bugs`, and `caveman` and `zoom-out` are gone. The
   glossary file is `GLOSSARY.md`: if you have a `CONTEXT.md` from an earlier version, the
   skills no longer look for it, and his changelog says to `git mv` it.

His `to-spec` and `to-tickets` also do the job of this template's `/write-a-prd` and
`/prd-to-issues`. Running both is harmless, since each is something you call by name, but you
only need one pair.

Source: https://github.com/mattpocock/skills

## pstack - engineering rigor, worth reading even if you never install it

Lauren Tan's skill library (poteto, Cursor and React core): 58 skills behind one sticky router,
`/poteto-mode`, which picks a playbook for the task and calls the other skills as its steps need
them. 24 of the 58 are standalone principles rather than procedures. The proof-standard skills are
the ones worth the read - `blast-radius`, where this template's certainty ladder came from, plus
`create-verification-skill` and `maintain-verification-skill`, which write and then maintain a
skill that teaches your agent to drive your actual app.

```text
# inside Cursor
/add-plugin pstack

# inside Claude Code
/plugin marketplace add cursor/plugins
/plugin install pstack@cursor-plugins
```

In Claude Code its commands carry a prefix, so `/poteto-mode` is `/pstack:poteto-mode`, and it
stays on the version you installed until you turn on auto-update for that marketplace. Its
README says both. Counts and install lines were checked against the repository on 2026-11-13.

**Collision warning.** Its principles are opinions, and some argue against this template's rules:
`principle-never-block-on-the-human` against pausing for a human decision, `no-comments` against
the doc comments some languages expect. Its `tdd`, `reflect` and `interrogate` overlap this
template's `/tdd`, `/learn`, and whatever automated reviewer you run. Read its principles against
your own AGENTS.md before installing all 58 - an agent holding two rule sets has no way to pick
between them.

Source: https://github.com/cursor/plugins/tree/main/pstack

## Impeccable - frontend design quality

Builds on Anthropic's frontend-design skill: 24 commands (`polish`, `audit`, `critique`,
`animate`, ...), 62 deterministic anti-"AI slop" detector rules, curated styles/palettes/font
pairings, 8 stacks (React, Next.js, Vue, Svelte, SwiftUI, React Native, Flutter, Tailwind).
Harness-agnostic: works with Claude Code, Cursor, Copilot, Gemini CLI, Codex.

```bash
# from the project root
npx impeccable install
# then inside your coding agent:
/impeccable init
```

Note: unlike the others, this installs per-project state - which fits, since design context
(audience, brand personality) is per-project.

Source: https://impeccable.style/ (pbakaus/impeccable)

## anydoc - documents into Markdown so your knowledge base can read them

Converts Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV and PDF into GitHub-flavored
markdown. Pure Rust, runs locally, no API key and no upload. It earns its place the day you turn
on `brain/` or any other markdown-indexed knowledge base: the index reads markdown, so a spec in
`.docx` or a PDF report sits in your docs tree unsearchable until something converts it.

```bash
npx skills add firecrawl/anydoc
```

It registers under the name **`convert-documents-to-markdown`**, not "anydoc" - searching your
skill list for "anydoc" finds nothing. There is also a plain CLI (`npx @firecrawl/anydoc`) and
Node, Python and Rust bindings if you would rather script it than call it from an agent.

**Check every PDF against the source before you keep the output.** Office formats convert
reliably. PDFs have two failure modes and only one of them is safe: an image-based PDF fails
loudly and writes nothing, but a design-heavy PDF can convert silently wrong - exit 0, confident
and plausible markdown, with digits dropped from numbers, words broken mid-token, and in one real
case a strikethrough inverted so a tagline claimed the opposite of the source. Do not let the
"text-based PDFs need no OCR" line reassure you here; the corrupted case was text-based. Never
point it at a whole folder in one pass either - use an allowlist, so nothing private or
deliberately kept out of the corpus gets converted back into it through a side door.

Source: https://github.com/firecrawl/anydoc

## Longshot - full-page screenshots an agent can actually take

Two surfaces over one capture engine: a Chrome/Brave extension for screenshots you take by hand,
and a headless CLI for the ones a script, CI job, or coding agent takes. The reason to prefer it
over a hand-rolled Playwright call is sticky headers - a scroll-and-stitch capture repeats them
down a tall image, and this suppresses them after the first tile. It drives your installed
Chrome, so nothing is downloaded and nothing is uploaded.

```bash
npx @craigcossairt/longshot --url https://example.com --full-page --out shot.png
```

Built for non-human callers: one JSON object on stdout, progress on stderr, and distinct exit
codes rather than a single failure state. It also writes a `.verdict.json` you can hand back as
`--baseline` on a later run, which is what turns a screenshot into something CI can fail on.

**Disclosure, because this list is otherwise third-party:** this is the template author's own
tool, MIT, first published 2026-09-10. Every other entry here had field use before it was
listed; this one has a thorough review and very little mileage. Judge it on the code.

**Limits:** `--cdp`, the flag that attaches to a browser you are already running so you can
capture logged-in pages, does not set `bypassCSP` - so a page with a restrictive CSP is covered
when Longshot launches the browser itself and not covered over an attached one. The extension is
sideload-only, with no Chrome Web Store listing. Needs Chrome, Chromium, or Edge installed.

Source: https://github.com/craigcossairt/Longshot

## T3 Code - every agent session in one window

An open-source app for desktop, web and phone that runs the coding agents you already have, side
by side: Claude Code, Codex, Cursor, OpenCode, Grok Build, Antigravity, Kiro, Pi, Muse Code, and
any agent that speaks ACP. It does not resell model access. Each agent signs in with your own
account and uses the plan you already pay for, so the app adds no bill of its own.

It earns its place the first time you want two things at once: a second session working while
the first one runs, a different model reviewing the first one's work (which this template asks
for on anything risky, see `docs/methodology/adversarial-review.md`), or a look at a long run
from your phone. Each thread can work in its own git worktree, so parallel sessions do not edit
the same files.

```bash
brew install --cask t3-code        # macOS
winget install T3Tools.T3Code      # Windows
```

Its README has the Linux packages and the other install routes. You need at least one coding
agent installed and signed in first: T3 Code drives agents, it is not one.

**With this template:** a thread working in its own worktree still has to claim its branch. Run
`bin/claim-branch.sh --acquire` from inside that thread's worktree. The lease is recorded in the
worktree's own git folder, and that record is how the push gate tells your push from another
session's. Nothing collides: used on this template's own repository, it added no files to the
working tree.

**Maturity:** MIT, and young. It was at version 0.1.9 when this entry was written (checked
2026-11-13), so expect it to change. Disclosure: this entry was written from a session running
inside it.

Source: https://github.com/pingdotgg/t3code

---

# Overlaps and collisions

Skill packs install into a shared namespace, and nothing warns you when two of them claim the
same name. This section is the one place that tracks it. Everything here is still worth using -
the point is to install it knowingly.

| Pack | Overlaps with | What you get if you ignore it |
|---|---|---|
| Matt Pocock's skills | `/tdd` (his `tdd` and `implement`), and your `CLAUDE.md`, which its setup skill edits | Two TDD workflows with different rules and no way for the agent to pick, plus rules written into a file only Claude Code reads |
| superpowers | `/tdd`, `/worktree`, the bug protocol and plan-first, plus an instruction at every session start to use its skills whenever one might apply | The pack's workflow chosen over this template's, on the pack's say-so |
| pstack | `/tdd`, `/learn`, plus principles that argue against rules in your `AGENTS.md` | An agent holding two rule sets that contradict each other |
| gstack | `/learn`, and your repo's `CLAUDE.md`, `.claude/settings.json` and `.claude/hooks/` if you run its team setup | A second `/learn` that writes somewhere else, and tracked files edited by an installer |
| gbrain | `brain/` | Two project memories, neither aware of the other |

## How name collisions actually work

Worth understanding once, because it lets you check any pack yourself.

Claude Code loads skills from two places: **user level** (`~/.claude/skills/`, shared by all your
projects) and **project level** (`.claude/skills/`, this repo). Almost every pack here installs
user-level. This template's skills are project-level. So a pack that ships a skill named `learn`
does **not** overwrite this template's `learn` - the two files sit in different places. What you
get instead is two skills answering to one name, and nothing tells you which one ran.

The destructive case is narrower and worth knowing: if a pack installs a skill at a name where
you already have a **user-level** skill of your own, the installer may replace your file outright.

Plugins are a third source, and the kindest one. A skill that arrives in a plugin is called with
the plugin's name in front (`/pstack:poteto-mode`, `mattpocock-skills:tdd`), so it cannot take a
name you already use. That removes the name collision and nothing else: two skills that both
claim to be how you do test-first work are still two, and the agent still has to choose.

To check a pack before installing, list the names it ships and compare them against your own
`.claude/skills/` and `.claude/commands/`. Note that a skill's installed name comes from the
`name:` line inside its `SKILL.md`, which is not always its folder name.

## superpowers - a pack that asks to be used for everything

Jesse Vincent's skill pack, and a popular one: planning, test-driven development, systematic
debugging, git worktrees, code review, verification before completion. It is here because of how
it loads, which matters more next to this template than what it contains.

Read from version 7.0.2 on 2026-11-13: its session-start hook puts the whole of its
`using-superpowers` skill into every session inside an `EXTREMELY_IMPORTANT` block, and that
skill says that if there is "even a 1% chance a skill might apply" the agent "ABSOLUTELY MUST
invoke the skill". Its `test-driven-development`, `using-git-worktrees`, `writing-plans` and
`systematic-debugging` skills cover the same ground as this template's `/tdd`, `/worktree`,
plan-first rule and bug protocol. So the agent starts every session holding two workflows for
the same jobs, and one of them has told it, in capitals, that it must win.

What was not measured here is how often that pulls an agent off this template's protocols in
practice. The text is certain; the size of the effect is not. If you want both, decide which
one is the authority for each job, say so in your `AGENTS.md`, and watch the first few sessions.
If you only installed it to try it, turn it off for this project in the project's own settings
rather than everywhere.

Source: https://github.com/obra/superpowers

## gstack - virtual engineering team, and it edits your repo

Opinionated persona commands (CEO product rethink, eng-manager architecture lock, design
critique, security audit, QA in a real browser, release engineer). Genuinely capable. Heavy
install (~GBs: bundled browser + node_modules) - machine-level, clone once:

```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
cd ~/.claude/skills/gstack && ./setup
```

Four things to know first. All four were checked against gstack v1.12.2.0 on 2026-09-21. It has
moved a long way since (v1.99.2.0 on 2026-11-13) and they have not been re-tested, so treat the
numbers below as that version's and check the behaviour yourself before relying on it.

**1. It installs under short names by default.** The installer offers short names (`/qa`, `/ship`,
`/review`) or namespaced ones (`/gstack-qa`). Short is the default in every path that does not
involve you typing: quiet mode, any non-interactive run, and the interactive prompt itself, which
auto-selects short after ten seconds. Of the 42 skills it ships, exactly one collides with this
template: **`learn`**. Choose namespaced at the prompt, or pass the flag, and the collision goes
away entirely.

**2. Installing over an existing user-level skill replaces it silently.** The installer links each
skill into place with `ln -snf`, which removes whatever is already at that path. Tested directly:
a `SKILL.md` of your own at a colliding name is replaced, exit code 0, no warning. On Windows the
replacement is a copy rather than a link, so the original content is simply gone. This does not
affect this template's skills, which are project-level - it affects any user-level skill of your
own that shares a name with one of gstack's 42.

**3. Its team setup edits files this template owns.** `gstack-team-init` appends a gstack section
to your repo's `CLAUDE.md`, creates `.claude/hooks/check-gstack.sh`, and adds an entry to
`.claude/settings.json`. This template's `CLAUDE.md` is deliberately an eleven-line pointer, and
its `settings.json` has exactly four hook entries. Skip team init, or expect to review what it
wrote.

**4. `/ship` and the push gate will fight.** gstack's release commands commit and push. If you
turned on this template's push gate, those pushes are refused until the checks have been recorded.
That is the gate working, not a bug - but the tempting fix is to start bypassing the gate by
reflex, at which point you no longer have one.

Also worth knowing, though neither is a collision: it reports anonymous skill-usage telemetry to
its author by default (set in `~/.gstack/config.yaml`), and its install instructions ask you to
write a line into your `CLAUDE.md` telling your agent never to use the built-in browser tools.
Your `AGENTS.md` is where your tool policy is decided; a line a vendor asks you to paste in is a
suggestion to evaluate like any other.

Source: https://github.com/garrytan/gstack

## gbrain - a second project memory

A separate project from gstack by the same author, despite the name and the bundled `/setup-gbrain`
skill that installs it. It is agent memory in Postgres: pages, chunks, embeddings, typed links, a
timeline. It attaches as an MCP server rather than as skills.

```bash
bun install -g github:garrytan/gbrain#stable
```

Its README (2026-11-13) now leads with a hosted service: the suggested setup points your agent
at `https://gbrain.io/mcp`, which means your project's notes live on their server. Running it
yourself is still documented (`gbrain setup claude-code` registers a local `gbrain serve`). The
comparison below was written against the self-hosted version and has not been re-checked.

**It overlaps `brain/` completely.** Both exist to feed relevant project context into your prompts.
Running both means two stores with two ingest paths and no shared notion of what is true. Pick one.
`brain/` is smaller, local, has no service dependency, and is already wired into this template's
hooks. gbrain is far more capable and costs more to run. If you pick gbrain, delete `brain/`.

**Its setup can ask for a Supabase personal access token.** One of its three storage options
provisions a new Supabase project for you, which requires a token that grants access to *every*
project in your Supabase account. The skill discloses this. The local PGLite option needs no
token at all and is the right default.

**Naming trap:** gstack ships its own scripts named `gstack-brain-*`. Those are unrelated to
gbrain - they sync gstack's local state to a private GitHub repo. Three different things, two
of them one letter apart.

Source: https://github.com/garrytan/gbrain

---

# Services & integrations

The service stack that earned its keep in the production setup this template was extracted
from. Rules of this list: one pick per category (not a directory), each entry says when it
*earns its place*, and the default is always free/built-in until you feel the pain it solves.
Most of these can wait - the entries marked "day 1" (a password manager above all) are the
exceptions.

| Category | Pick | When it earns its place |
|---|---|---|
| Issue tracking | GitHub Issues to start; **Linear** when the backlog outgrows it | Day 1 for Issues (free, zero setup, agents read/write via `gh`). Move to Linear when you're juggling priorities across many issues and need cycles/projects - it has an MCP server, so agents work the backlog directly. |
| Automated PR review | **CodeRabbit** | As soon as you're merging AI-written code you can't fully review yourself - an automated second reader catches real bugs. Free for public repos; a private repo gets a 14-day trial and is paid after that, which matters because most first projects are private. Caveat: treat it as a reviewer, not a gate; question its premise before applying a remedy, and never merge on its check status alone - read the actual comments. |
| Error tracking | **Sentry** | The day real users touch the product. Before that, local logs are enough. Free tier is generous for a small app; agents can triage straight from its MCP server. |
| Uptime monitoring | **UptimeRobot** | The day something is deployed that users depend on. Free tier covers a small site. |
| Product analytics | **PostHog** | When you start making product decisions and need evidence instead of vibes. Free tier is generous. |
| CI | **GitHub Actions** | First time a broken push costs you an evening. Start with lint + test on PR; it's free for public repos and cheap for private ones. |
| Secrets | A password manager (**Bitwarden**, 1Password) | Day 1, non-negotiable. Real values live there; repos get `.example` files only. The template's hooks enforce the repo side. |
| Backend | **Supabase** (if you need a database + auth) | Day 1 if your product stores user data and you don't have strong stack opinions: Postgres, auth, storage, and functions in one, generous free tier, and an MCP server so agents can manage the schema. Two things the free tier does that surprise people: a project nobody touches for a week is paused until you wake it, and the built-in email sender is for testing only (2 messages an hour, to your own team's addresses), so connect a real email provider before your first outside signup. If you do have stack opinions, use them - this row is a default, not a mandate. |
| Web hosting | **Vercel** | The day you have a web app or site to put in front of anyone. Free hobby tier, git-push deploys, and MCP/CLI so agents can ship and inspect deployments. Vercel's terms keep the free tier to personal or non-commercial use, so budget for the paid plan from the day the site earns money. |
| Dependency security | **OSV.dev** to start; **Socket** for supply-chain depth | OSV is day 1 - free, no signup, already wired into this template's `/review-dependency-updates` skill. Add Socket when you want supply-chain risk scoring (maintainer changes, install scripts) beyond known CVEs. |
| Docs & knowledge | Markdown in the repo to start; **Notion** at company stage | This template's whole philosophy: docs live in git where agents read them for free. Notion earns its place when non-code collaborators and business ops appear (see `growing-into-a-workspace.md`). |
| Codebase audits | **AuditBuffet** | Pre-launch, or whenever you suspect the AI has quietly accumulated slop. Audit prompts run locally inside your coding agent (your code never leaves your machine); free basic scan, ~$9/mo for the full catalog at time of writing. |
| Design & visuals | Pick one rung, not a shelf. **Never designed anything:** your coding agent + a design skill for in-app UI, plus **Claude Design** or **Google Stitch** for things that are not your app. **Working with a designer, or design is the product:** **Figma**, and **Paper** (paper.design) if you want design and code to be one artifact instead of two that drift. | Most solo founders need less design tooling than they think, and the failure mode is collecting accounts instead of shipping screens. The Impeccable skill above covers in-app UI. Claude Design (Anthropic) and Google Stitch earn their place for decks, one-pagers and landing mockups - treat their output as a first draft you then tokenise, because both hand you a wall of literal values. Figma when you collaborate with an actual designer. See `DESIGN.md` for the rules that outlast whichever tool you pick. |

Product offerings, pricing, and free-tier limits change regularly. Treat this list as
exemplary, not definitive: it shows what one real setup uses and why, but do your own research
and pick the tool that fits your needs before committing - especially to a paid plan.

## Adding to this list

Criteria for a skill-pack entry: actively maintained, installable from source with one command,
and worth recommending to a teammate on day 1. Before adding one, list the skill names it ships
and diff them against `.claude/skills/` and `.claude/commands/`; anything that overlaps, or any
installer that writes into the repo, gets a row in **Overlaps and collisions** above. A collision
recorded in one entry's prose and nowhere else is a collision the next reader will not find.

Criteria for a service entry: it earned its keep in a real project, has a usable free tier or
clear pricing, and ideally has an MCP server or CLI so agents can operate it, not just humans.
