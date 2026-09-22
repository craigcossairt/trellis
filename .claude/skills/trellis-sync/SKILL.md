---
name: trellis-sync
description: Check this project against the template it was made from, show what changed upstream, and apply only what the user picks. Use when asked to "check for template updates", "sync with trellis", "is my template copy out of date", "pull in upstream template changes", "what changed in the template".
---

# Sync a copy against the template it came from

A copy made from a GitHub template has no git relationship to the template, so
there is no "git pull" for it. This procedure closes that gap: it reports what
upstream changed, and applies only what the user chooses.

## The rule that matters

**You do not classify anything yourself.** `bin/trellis-sync.sh` decides which
bucket each file is in. Read its output and act on that. If you eyeball the
files and form your own opinion, you will eventually tell someone a file is
safe to overwrite when they spent an afternoon editing it.

## 1. Run the check

```bash
bash bin/trellis-sync.sh --porcelain
```

Each line is `<bucket>\t<path>`. Exit codes: **0** nothing to take, **1** there
is something, **2** could not tell.

**Exit 2 is not "you are up to date."** It means the check did not run - no
manifest, an unreachable upstream, an empty response. Report what it said and
stop. Never summarise a failed check as good news.

If there is no `.trellis/manifest`, this copy predates the sync mechanism or was
not made from the template. Say so. Do not offer to generate one from the
current tree: a manifest built from an already-modified copy records your edits
as if upstream had shipped them, and every future sync inherits that lie.

## 2. Read the buckets back to the user

| Bucket | Means | Default |
|---|---|---|
| `apply` | Upstream changed it; this copy has not | Offer to take it |
| `added` | Upstream has a new file this copy lacks | Offer to take it |
| `conflict` | Changed upstream **and** here | Ask. Never auto-apply |
| `removed` | Upstream deleted it; this copy still has it | Ask. Deleting is theirs to choose |
| `deleted` | Deleted here; upstream still ships it | Mention once. Assume deliberate |
| `localonly` | Changed here, unchanged upstream | Nothing to do. Do not list these individually |

Lead with `apply` and `added`, because those are the cheap wins. Summarise
`localonly` as a count. A report where everything looks urgent gets skimmed.

## 3. Apply what they pick

**You do not fetch or write files yourself.** One command does it:

```bash
bash bin/trellis-sync.sh --apply <path> [--apply <path> ...]
```

It resolves the upstream to a single immutable commit, takes the bytes for each
path from that same commit, checks each one against its hash in the upstream
manifest, and only then moves it into place. A file that fails any of that is
not written and the run exits 2.

The earlier version of this section told you to run
`gh api "repos/<upstream>/contents/<path>" ... > "<path>"` by hand. Do not go
back to it, and do not reach for it when the script is inconvenient. It was
wrong twice over. That URL is the **default branch**, while the buckets above
are computed from the release manifest, so the bytes written were not the bytes
that had been classified. And `>` truncates the destination *before* the fetch
runs, so a failed fetch left an **empty file** where the adopter's file had
been. That is measured, not theoretical: 42 bytes to 0.

Rules that still need you:

- **Show the diff before applying**, for every file, including `apply`.
  "Safe to take" means nobody edited it here, not that they wanted the change.
- **Never apply a `conflict` file without the user having seen both versions.**
  Taking an update is a whole-file write. There is no merge.
- If a file needs a matching change elsewhere - a skill and its Cursor router,
  a hook and its `settings.json` entry - take both or neither.
- `removed` is not applied by this tool. Upstream deleting a file is not the
  same as you wanting it gone; delete it yourself if you agree.

## 4. Recording happens automatically. Do not "regenerate the manifest"

`--apply` rewrites only the manifest lines for the files it actually took.
Everything else is left exactly as it was, which is what makes a declined
update show up again next time instead of disappearing.

**Never run `bin/trellis-manifest.sh --write` in a copy.** It hashes every
tracked file, so it records *your* work as though the template had shipped it.
Measured on a fixture: a template file the adopter had edited and declined went
from `localonly` to `apply` - "SAFE TO TAKE" - on the very next run, and their
own `src/app.ts` appeared under "REMOVED UPSTREAM - decide whether to keep". The
command now refuses to run outside the template, but the reason matters more
than the guard: the manifest records what the TEMPLATE shipped, and the moment
it records anything else, every later sync inherits that.

If the user declined everything, nothing is written - not the manifest, not the
version. Declining is not syncing, and recording it as one would hide those same
updates next time.
