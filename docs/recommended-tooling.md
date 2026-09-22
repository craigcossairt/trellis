# Recommended third-party tooling

Optional, battle-tested third-party skill packs worth installing alongside this template. Most
are **user-level installs** (they live in `~/.claude`, shared across all your projects) - install
those once per machine, not per project. Two are not: pstack is a Cursor plugin, and Impeccable
installs per project. Each entry states its own scope. They are referenced here rather than
vendored so they update from source and their licensing stays clean.

**Read [Overlaps and collisions](#overlaps-and-collisions) before you install anything.** Skill
packs install into a shared namespace. Some of the packs below ship a skill under a name this
template already uses, and one of them edits files this template owns.

## Matt Pocock's skills - engineering discipline

Eleven skills that force the agent to slow down: grill you on the plan, run a real debug loop,
zoom out before architecting. (`/grill-me`, `/grill-with-docs`, `/diagnose`, `/zoom-out`,
`/improve-codebase-architecture`, `/to-prd`, `/to-issues`, `/caveman`, `/write-a-skill`, ...)

```bash
npx skills@latest add mattpocock/skills
```

The installer is interactive - pick the skills you want and which coding agents to install them
for, then run `/setup-matt-pocock-skills` inside your agent.

**Collision warning:** his `tdd` and `implement` skills overlap with this template's `/tdd`
command and methodology docs. Pick one TDD authority - either skip installing his `tdd`, or
delete this template's version. Running both gives the agent two conflicting workflows.

Source: https://github.com/mattpocock/skills

## pstack - engineering rigor, worth reading even if you never install it

Lauren Tan's skill library (poteto, Cursor and React core): 44 skills behind one sticky router,
`/poteto-mode`, which picks a playbook for the task and calls the other skills as its steps need
them. 21 of the 44 are standalone principles rather than procedures. The proof-standard skills are
the ones worth the read - `blast-radius`, where this template's certainty ladder came from, plus
`create-verification-skill` and `maintain-verification-skill`, which write and then maintain a
skill that teaches your agent to drive your actual app.

```text
/add-plugin pstack     # inside Cursor
```

**Cursor only.** It ships as a Cursor plugin and has no official Claude Code install. Unofficial
ports and mirrors exist but are not the author's, so if you are not on Cursor, read the source
and graft what you want rather than trusting a fork to stay current.

**Collision warning.** Its principles are opinions, and some argue against this template's rules:
`principle-never-block-on-the-human` against pausing for a human decision, `no-comments` against
the doc comments some languages expect. Its `tdd`, `reflect` and `interrogate` overlap this
template's `/tdd`, `/learn`, and whatever automated reviewer you run. Read its principles against
your own AGENTS.md before installing all 44 - an agent holding two rule sets has no way to pick
between them.

Source: https://github.com/cursor/plugins/tree/main/pstack

## Impeccable - frontend design quality

Builds on Anthropic's frontend-design skill: 23 commands (`polish`, `audit`, `critique`,
`animate`, ...), 45 deterministic anti-"AI slop" detector rules, curated styles/palettes/font
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

---

# Overlaps and collisions

Skill packs install into a shared namespace, and nothing warns you when two of them claim the
same name. This section is the one place that tracks it. Everything here is still worth using -
the point is to install it knowingly.

| Pack | Overlaps with | What you get if you ignore it |
|---|---|---|
| Matt Pocock's skills | `/tdd`, and `implement` | Two TDD workflows with different rules and no way for the agent to pick |
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

To check a pack before installing, list the names it ships and compare them against your own
`.claude/skills/` and `.claude/commands/`. Note that a skill's installed name comes from the
`name:` line inside its `SKILL.md`, which is not always its folder name.

## gstack - virtual engineering team, and it edits your repo

Opinionated persona commands (CEO product rethink, eng-manager architecture lock, design
critique, security audit, QA in a real browser, release engineer). Genuinely capable. Heavy
install (~GBs: bundled browser + node_modules) - machine-level, clone once:

```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
cd ~/.claude/skills/gstack && ./setup
```

Four things to know first. All four were checked against gstack v1.12.2.0 on 2026-09-21.

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
bun install -g github:garrytan/gbrain
claude mcp add gbrain -- gbrain serve
```

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
| Automated PR review | **CodeRabbit** | As soon as you're merging AI-written code you can't fully review yourself - an automated second reader catches real bugs. Free for public repos. Caveat: treat it as a reviewer, not a gate; question its premise before applying a remedy, and never merge on its check status alone - read the actual comments. |
| Error tracking | **Sentry** | The day real users touch the product. Before that, local logs are enough. Free tier is generous for a small app; agents can triage straight from its MCP server. |
| Uptime monitoring | **UptimeRobot** | The day something is deployed that users depend on. Free tier covers a small site. |
| Product analytics | **PostHog** | When you start making product decisions and need evidence instead of vibes. Free tier is generous. |
| CI | **GitHub Actions** | First time a broken push costs you an evening. Start with lint + test on PR; it's free for public repos and cheap for private ones. |
| Secrets | A password manager (**Bitwarden**, 1Password) | Day 1, non-negotiable. Real values live there; repos get `.example` files only. The template's hooks enforce the repo side. |
| Backend | **Supabase** (if you need a database + auth) | Day 1 if your product stores user data and you don't have strong stack opinions: Postgres, auth, storage, and functions in one, generous free tier, and an MCP server so agents can manage the schema. If you do have stack opinions, use them - this row is a default, not a mandate. |
| Web hosting | **Vercel** | The day you have a web app or site to put in front of anyone. Free hobby tier, git-push deploys, and MCP/CLI so agents can ship and inspect deployments. |
| Dependency security | **OSV.dev** to start; **Socket** for supply-chain depth | OSV is day 1 - free, no signup, already wired into this template's `/review-dependency-updates` skill. Add Socket when you want supply-chain risk scoring (maintainer changes, install scripts) beyond known CVEs. |
| Docs & knowledge | Markdown in the repo to start; **Notion** at company stage | This template's whole philosophy: docs live in git where agents read them for free. Notion earns its place when non-code collaborators and business ops appear (see `growing-into-a-workspace.md`). |
| Codebase audits | **AuditBuffet** | Pre-launch, or whenever you suspect the AI has quietly accumulated slop. Audit prompts run locally inside your coding agent (your code never leaves your machine); free basic scan, ~$9/mo for the full catalog at time of writing. |
| Design & visuals | Your coding agent + a design skill to start; **Claude Design** for visuals beyond the app; **Figma** when a designer joins | Most solo founders need less design tooling than they think - the Impeccable skill above covers in-app UI. Claude Design (Anthropic, research preview) earns its place for decks, one-pagers, and landing mockups. Figma when you collaborate with an actual designer. |

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
