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
  database + storage in one service. See #12.
