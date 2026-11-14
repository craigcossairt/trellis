# Skill routers (`.agents/skills/`)

Codex discovers repository skills under `.agents/skills/`. So does Grok Build
(`grok inspect` resolves them here, CLI 1.0.77). Muse Code, Antigravity and
Gemini CLI say in their documentation that they read this directory too; none of
the three has been run against this template. Each router has
`name` and `description` frontmatter and one backticked, repository-relative
target under `.claude/skills/` or `.claude/commands/`.

Use LF line endings and `---` frontmatter fences. The validator accepts only
`name` and `description`, each once on a single line. Use non-empty plain strings
starting with a letter, or quote them with JSON-style double quotes or YAML
single quotes (double any embedded apostrophe). Quote boolean/null words and
values containing `: ` or a comment-like ` #`. Collections, aliases, multiline
values, and extra fields are outside this router format; put extra instructions
in the canonical procedure.

Maintain the procedure only at that target. Add or remove its router in the same
commit. All retained canonical procedures need routers while this adapter is
present. Delete `.agents/` to opt out entirely. That removes the skills from
every tool named above, not only from Codex.

In Codex, invoke a skill by name, for example `$setup` or `$trellis-survey`, or
describe the task. In Grok Build the same skill is `/setup`. Run `python3 bin/validate-codex.py` to check wiring; on Windows use
`python`. This checks files, not whether a running Codex session has loaded them.
