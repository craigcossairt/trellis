# Writing your own skills

Sooner or later you'll catch yourself giving the AI the same multi-step instructions for the
third time. That's a skill: a markdown file that teaches the procedure once, so every future
session already knows it. This page is the 10-minute guide to writing one that actually works.

## The basics

- **One skill = one procedure.** "Prepare a release" is a skill. "Do engineering" is not.
- **Format:** a `SKILL.md` file in `.claude/skills/<name>/` (Claude Code) with frontmatter:

  ```markdown
  ---
  name: prepare-release
  description: Cut a release - bump version, update changelog, tag, push. Use when asked to 'cut a release', 'ship a version', 'prepare the release'.
  ---
  (numbered steps here)
  ```

- **The description is the trigger.** Include the literal phrases you'd naturally say when you
  want it ("Use when asked to '...'") - that's how the agent knows to reach for it.
- **Write steps you'd hand a competent new hire:** numbered, concrete, with the exact commands
  and file paths. Say what "done" looks like. Say what to do when a step fails.
- **Test it in a fresh session.** If a clean session with no context can follow it, it works.
  If you had to explain something extra, that explanation belongs in the skill.

## The hardening checklist

Before you call a skill finished, ask these six questions. Most skills need only one or two of
these, but knowing the list keeps you from writing a skill where a stronger mechanism was
available:

1. **Should this be a hook instead of a skill?** A skill only helps when someone invokes it.
   If the point is "never let X happen" (bad edits, secrets in commits), wire it as a hook that
   fires on every edit - passive guardrails beat a command nobody remembers to run. (This
   template's `.claude/hooks/` are examples.)
2. **Does it load only what it needs?** If the skill has a big reference (a style guide, an API
   doc), keep it in a separate file and have the skill read it only when the task needs it.
   A skill that dumps everything into context every time crowds out the actual work.
3. **If it reviews something, is the reviewer blind?** Second opinions are only worth having if
   they're independent. Don't show reviewer #2 what reviewer #1 (or the linter) said until it
   has committed its own take - then synthesize. An anchored reviewer is a rubber stamp.
4. **Should runs compound?** If the skill runs repeatedly against the same thing (an audit, a
   critique, a brief), have it write a dated snapshot that the next run reads. Otherwise every
   run rediscovers the same findings from zero.
5. **Will the weakest model follow it?** You may run cheaper models for routine work. Write
   gates they can't rationalize past: "NEVER X", "STOP and ask if Y", numbered hard steps -
   not "use good judgment", which strong models interpret and weak models skip.
6. **Does it degrade loudly?** If the skill needs a tool, key, or capability that might be
   missing, make step 1 check for it and stop with a clear message. A skill that silently
   half-works is worse than one that says exactly what it's missing.

## Credit

The hardening checklist distills ideas from Paul Bakaus's "The Dark Arts of Skill Engineering"
workshop (https://github.com/pbakaus/impeccable-talks) alongside patterns from the production
setup this template was extracted from. His talk goes considerably deeper (per-harness
compilation, live browser loops) - worth a read once you're past your first few skills.
