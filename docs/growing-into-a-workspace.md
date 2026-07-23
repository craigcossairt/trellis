# Growing into a workspace

This template starts you with **one repo = one project**. That's right for a side project,
hackathon, or single app. But if the project becomes a venture, it accumulates things that don't
belong in a code repo - legal docs, marketing assets, photos, investor materials - and usually a
second repo (marketing site, admin tool). This doc is the graduation path.

## When to graduate

Any two of these and it's time:

- A second git repo appears (website, admin, API)
- Non-code artifacts are piling up (contracts, brand assets, research, photos) with no home
- You're running agent sessions about the *business* (marketing copy, legal review, planning)
  that have nothing to do with code
- Multiple people or machines need the non-code files synced

## Target layout

```
<Venture>/                     # workspace root - NOT a git repo
├── AGENTS.md                  # workspace-level: company context, cross-repo conventions
├── CLAUDE.md                  # thin: @AGENTS.md
├── Files/                     # non-code life of the venture (file-sync'd, not git)
│   ├── Context Files/         # working docs - see "What Context Files holds" below
│   ├── Legal/
│   ├── Marketing/
│   └── Images/
└── Code/
    ├── <app-repo>/            # git repo, started from trellis
    │   └── AGENTS.md          # repo-level: stack, commands, code conventions
    └── <website-repo>/        # git repo, its own AGENTS.md
```

Division of labor between the two AGENTS.md levels:

| Level | Owns | Examples |
|---|---|---|
| Workspace | Who/what the venture is, brand, cross-repo conventions, source-of-truth pointers, file structure | company stage, tracker URL, brand voice doc, "decisions go in Files/Context Files/decision-log.md" |
| Repo | Everything needed to work in that codebase alone | stack, build/test commands, architecture, repo-specific gotchas |

Nothing appears at both levels. The workspace file points down ("each repo has its own
AGENTS.md"); repo files never point up (they must work standalone for tools that can't see the
parent directory).

## What Context Files holds

The canonical set that a venture-stage `Files/Context Files/` grows into. Each is one file with
one owner-topic; agents read the relevant ones per task instead of loading everything always:

- **about-me.md** - founder background and working style (graduates up from the repo's
  `docs/about-me.md`)
- **company-brief.md** - investor-facing context: business model, target customer, go-to-market,
  fundraising posture. Deliberately does NOT exist at repo stage - until then it would just
  duplicate AGENTS.md's Project section.
- **decision-log.md** - graduates up from the repo once decisions stop being purely technical
- **voice-and-style.md** - brand voice and content principles, read before any external writing

Rule of thumb for any new context file: one topic, one owner file, and ask "does every session
need this?" - if not, it's a context file agents read on demand, not AGENTS.md content.

## Mechanics and caveats

- **The workspace root is not a git repo.** Repos live under `Code/` and sync via git. The rest
  of the workspace syncs via a file-sync tool (Syncthing, Dropbox, ...). Don't nest git repos
  inside a git repo, and don't put `Files/` (binary-heavy, private) under git.
- **Cloud-sync eviction warning:** if the sync tool does placeholder/on-demand files
  (iCloud "Optimize Storage", OneDrive Files On-Demand), exclude anything a search index or
  agent tooling reads - evicted stubs cause hangs and phantom-missing files.
- **Parent-directory context is harness-specific.** Claude Code launched inside
  `Code/<app-repo>/` also reads the workspace CLAUDE.md above it; Cursor/Codex/Gemini opened at
  the repo root do not. That's why repo-level AGENTS.md must stand alone - the workspace level
  is enrichment, not a dependency.
- **Run business sessions at the workspace root, code sessions at the repo root.** The working
  directory picks the context level for you.
- **The brain moves up.** If you initialized `brain/` in the repo, a workspace-level corpus
  (all repos' docs + Files/Context Files) is usually more valuable once the venture has real
  history. Keep the brain OUT of cloud-synced folders (see eviction warning).

## Parallel sessions: park the main checkout

Once several agent sessions (or you plus an agent) work the same machine, the main checkout of
each repo becomes shared state: session A switching branches yanks the tree out from under
session B mid-edit. The pattern that survives this:

- **The main checkout stays parked on the default branch.** Nobody switches it, ever.
- **All branch work happens in linked worktrees** - `git worktree add ../<repo>-wt-<task> -b
  <branch>` - one worktree per task, one session per worktree, removed when the branch merges.
- `git pull` on the main checkout is fine. `git switch`, `git checkout <branch>`, and
  `git reset --hard` there are not - each moves HEAD or rewrites the shared tree.
- **Enforce it, don't just document it.** A PreToolUse hook that blocks branch-switching
  commands in the main checkout turns the rule from etiquette into a guardrail - the same
  fail-closed philosophy as the push gate, whose relative `core.hooksPath` already covers
  every linked worktree.

## Migration steps (about an hour)

1. Create `<Venture>/` with `Files/` and `Code/`, move the existing repo into `Code/`.
2. Write the workspace AGENTS.md (skeleton below) + a thin CLAUDE.md (`@AGENTS.md`).
3. Move venture-level content out of the repo: `docs/about-me.md` and (usually) the decision
   log graduate to `Files/Context Files/` once decisions stop being purely technical. Leave
   repo gotchas and methodology docs in the repo.
4. Set up file sync for the workspace; verify the repo still pushes/pulls normally from its new
   path (update any IDE/terminal shortcuts and scheduled tasks that hardcode the old path).
5. Start the second repo from trellis into `Code/`.

## Workspace AGENTS.md skeleton

```markdown
# AGENTS.md - <Venture Name> (workspace)

> Workspace-level context. Each repo under Code/ has its own AGENTS.md for code conventions -
> read that one for code work. This file owns what's true across the whole venture.

## Company
name, one-liner, stage, owner

## Current State - Source of Truth Pointers
- Priorities: <tracker URL>
- Decisions: Files/Context Files/decision-log.md
- This file owns stable conventions only ("true in 6 months?")

## Repos
| Path | What | Stack |
|---|---|---|
| Code/<app> | | |
| Code/<website> | | |

## Brand / Voice
(or a pointer to Files/Context Files/voice-and-style.md)

## Folder Structure
(the workspace tree, kept to a map)

## Rules
(workspace-level housekeeping: where decisions get logged, what agents may do
autonomously across repos)
```
