---
name: build-verification-skill
description: Build this project's verification skill - a small CLI that drives the running app and captures evidence, plus a feature map of what exists and how to reach it - and the CI check that keeps the map current. Use when asked to 'build a verification skill', 'let the agent drive the app', 'make a feature map', 'the agent keeps guessing what a bug report means', or before relying on an agent to reproduce bugs.
---

# Build a verification skill

An agent can only be trusted with a change it can check for itself, and reading the code is not
checking it. This skill builds the two pieces that let it check: a **lever** that drives the real
running app and captures proof, and a **map** that turns a vague report ("the badge is wrong ???"
plus a cropped screenshot) into a specific feature, screen and set of commands.

Adapted from `create-verification-skill` in Lauren Tan's pstack (see CREDITS.md).

The output is a project skill, `.claude/skills/verify-<app>/`, and one script. Nothing here is
done until step 6 has run once against a real build: a verification skill that was never
executed is a draft.

## 1. Build the lever: a CLI, not a document

Prose an agent re-derives every session is not a tool. Write one script (`bin/control-app.sh` or
the project's equivalent) with subcommands:

| Subcommand | Does |
|---|---|
| `doctor` | Read-only: is this instance worth driving? Device or browser present, app installed, which build |
| `goto <route>` | Jump the running app to a screen, through whatever deep-link or URL mechanism exists |
| `screenshot [path]` | Capture evidence |
| `dump [path]` | Capture the UI tree, where the platform exposes one |
| `cleanup` | Remove this run's scratch; never touch the evidence directory |

Design rules:
- **Exit 0 ok, 1 a determined negative, 2 could not tell.** 2 never collapses into 0: "I could
  not check" is not "it is fine".
- `--json` on anything an agent parses; `--dry-run` on anything with a side effect; `--help` is
  the canonical surface.
- **Refuse production.** The lever drives a non-production build against seeded accounts.
- **Derive, never hardcode.** If jumpable routes are declared in the app's router, read them
  from there, so the lever and the app cannot drift.
- Errors say what to do instead, not only what failed.

## 2. Guard every input that crosses a shell boundary

These are the defects a stubbed test suite cannot see, measured on a real device run:

- **A remote shell re-parses its argument list.** `adb shell <args>` (and `ssh host <args>`)
  joins argv into ONE string and runs it in the remote shell, so a URL containing `&`
  backgrounds the command and runs the rest as a separate one. Quote the value for the remote
  shell, and make that safe by **refusing any input that is not one line of an allowlisted
  character set** before it is used. `grep -F` treats a pattern containing a newline as several
  patterns, so an allowlist lookup alone passes `"/allowed<newline>';rm -rf /;'"`.
- **Git Bash (MSYS) rewrites path-like arguments** before a native `.exe` sees them, so
  `/sdcard/x` reaches the tool as `C:/Program Files/Git/sdcard/x`. Export `MSYS_NO_PATHCONV=1`
  for a script whose native-tool arguments are remote paths, then convert LOCAL paths explicitly
  (`cygpath -w`, which is absent off Windows).
- **Assert on the argv the stub actually received,** never on a `--dry-run` display line. The
  display can be quoted correctly while the command that runs is not.
- **Unset inherited environment in the test** for any variable the script is supposed to set
  itself, or the case passes vacuously on a machine that already sets it.

## 3. Write the skill

`.claude/skills/verify-<app>/SKILL.md` with these six sections, each naming its subcommand:

- **Launch** - the exact commands that build and start a non-production instance, and what
  "ready" looks like. Prefer a visible marker (an environment ribbon, a banner) over `doctor`:
  `doctor` can confirm an app is installed, not that it is the right build talking to the right
  backend.
- **Doctor** - run before the first drive and after any drive that behaved oddly. A sick
  instance reports as a broken feature, the most expensive false finding there is.
- **Drive** - compute taps from the UI tree, never from a screenshot. When a node is missing but
  something scrollable is on screen, scroll and re-dump before concluding it is absent. Record
  platform quirks here (for example: text fields that dump without their label, a keyboard that
  hides the button you need).
- **Evidence** - capture the action AND the resulting state; exercise the real user path, never
  an internal setter or a seeded shortcut; check side effects (the row written, the message
  delivered to the other account). **Gitignore the evidence directory**: screenshots carry
  personal data.
- **Cleanup** - removes scratch only. Afterwards, list the evidence directory and confirm the
  files are still there; do not assume it.
- **Isolation** - can two drivers run side by side? Usually only on different devices AND as
  different accounts, because state lives on a shared backend. If there is no lock, say so.

## 4. Write the feature map

`.claude/skills/verify-<app>/features/`:

- **`README.md` is the map itself**, not an index: baseline preconditions every drive assumes
  (build, signed-in account, feature gates), a role table of seeded accounts **read from the
  live environment** rather than from a doc, the feature list grouped by area, a full-sweep
  order (least to most state-changing), driving conventions, and an **Unmapped routes** list
  where every entry carries a reason.
- **One file per feature**, with exactly four H2s in this order: `## Sub-features`,
  `## How to get to it (user POV)`, `## Driving it with <lever>`, `## Gotchas`. Fixed headings
  are what make the map sweepable. Ground every handle in visible text or accessibility labels
  and cite `file:line` for every gotcha.
- **`multi-surface-journeys.md`**, read last: flows that need two accounts or two devices. Proof
  lives on the side that did NOT act.

Start with three to five features. The check in step 5 and the maintenance in step 7 grow it.

## 5. Keep the map current with a check, not a routine

A map is only useful while it is true, and a doc that claims coverage is not coverage. Write
`bin/check-feature-map.sh` and run it in CI, including when the router file changes:

1. Every jumpable route is either driven by a feature file (`<lever> goto <route>`, matched
   exactly, never as a substring) or listed under Unmapped routes with a non-empty reason.
2. The unmapped list cannot go stale: a listed route that is also mapped, or no longer jumpable,
   fails.
3. Every feature file keeps the four H2s.
4. No feature file or journey drives a route that is no longer jumpable.

Fail closed: an unreadable router, an empty route set, a missing README, or no feature files is
exit 2, never clean. A flag given without its value is refused, not looped on (`shift 2` with one
argument left shifts nothing in bash). Pin the checker with a mutation-validated suite
(`/pin-guardrail`).

## 6. Run it once, end to end

Launch, doctor, drive one mapped feature, capture evidence, clean up, and confirm the evidence
survived. The first real run is where the defects in step 2 show up; expect to fix the lever.
Record each one as a gotcha and pin it with a test that fails when the fix is reverted.

## 7. Maintain

When a user-facing feature changes, its feature file changes in the same PR. Periodically audit
whether each file is still TRUE (strings, taps, accounts) by running its Driving section; the
check in step 5 cannot see that.
