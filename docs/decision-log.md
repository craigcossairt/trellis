# Decision Log

What was decided, when, and why. **Decisions only** - not specs, not current state, not
implementation details. Reference issue IDs instead of embedding detail: the ticket owns WHAT
was built, this file owns WHY it was decided that way.

**There is no length cap, and do not add one without measuring first.** The obvious rule to
write here is "one line per decision, never more than two", and it does not survive contact
with a real log. Measured across the whole life of the log this template was extracted from:
**2 entries out of 540 came in under 200 characters, and both were bookkeeping notes rather
than decisions** - none of the oldest 100, none of the newest 100, with mean entry length
growing from 481 to 1447 characters. A rule with a 0.4% compliance rate is not a strict rule,
it is a fiction that makes every real entry read as a violation, and rules nobody satisfies
teach agents that the rules here are decorative.

So: one line is fine when one line is enough. The reasoning is usually the part worth having
later, so spend the words where it is load-bearing and stop when it stops.

Format: `- **YYYY-MM-DD** - Decision description. See <issue-ref>.`

---

- **2026-07-01** - (Example - delete me) Chose Supabase over a custom backend: solo team, auth +
  database + storage in one service. See #999.
- **2026-09-21** - Cut v1.0 and adopted tagged releases. A template copy has no git ancestry with the template, so there was no way to tell a file the owner edited from one the template changed, and the README's advice was to skim upstream commits by hand once a month. .trellis/manifest now records what each release shipped, and bin/trellis-sync.sh classifies a copy against it. Tagging is what makes the manifest mean something: it describes a RELEASE, so it is regenerated when one is cut rather than on every commit, and CI deliberately does not require it to match main.
- **2026-09-22** - Moved applying and recording a template update out of the sync SKILL and into bin/trellis-sync.sh --apply, and made bin/trellis-manifest.sh --write refuse to run inside a copy. The skill had told every copy to fetch with `gh api .../contents/<path> > "<path>"` and then record the result with `--write`. Both were wrong. `--write` hashes `git ls-files`, so in a copy it records the adopter's own tree as though the template had shipped it: reproduced on a fixture, a template file they had edited and DECLINED moved from `localonly` to `apply` - reported as "SAFE TO TAKE" - on the very next run, and their own src/app.ts turned up under "REMOVED UPSTREAM - decide whether to keep". The same skill file forbade exactly this fifty lines earlier, which is the part worth remembering: the contradiction was plain text in one file and invisible to the model that wrote both halves. The redirect was the second defect - `>` truncates the destination before the fetch runs, so a failed fetch left an empty file where the adopter's file had been (measured, 42 bytes to 0), making the skill's own rule "a failed fetch is a stop, not a skip" unreachable. --apply now resolves ONE immutable commit for the manifest and every file, verifies each fetch against its manifest hash before the destination is touched, lands by rename, and rewrites only the manifest lines it actually took. Also removed the .trellis/baseline read: nothing ever wrote one, so nothing was broken - it was armed, not firing, and the moment a setup wizard wrote one every answer the adopter typed would have become SAFE TO TAKE, because taking an update is a whole-file write. Found by a cross-model review (Grok 4.7) of work written by Claude; see docs/methodology/adversarial-review.md, which this round is the worked example for.
- **2026-09-22** - Dropped the paths filter on hooks-ci. It listed shell scripts, .githooks, .claude, .cursor and .grok, and so excluded the inputs of two checks it ran: the credits gate reads docs/recommended-tooling.md and CREDITS.md, and the manifest gate reads .trellis/manifest. A pull request touching only those ran neither, while docs/harness-support.md told readers the job runs on every pull request. The job is lint plus hermetic suites and finishes in seconds, so the filter bought nothing and cost the coverage the docs promised.
