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

## 3. Apply what they pick, one file at a time

For each accepted path, fetch that file from upstream and write it:

```bash
gh api "repos/<upstream>/contents/<path>" -H 'Accept: application/vnd.github.raw' > "<path>"
```

`<upstream>` comes from `.trellis/source`. If `gh` is unavailable, use
`curl -fsSL "https://raw.githubusercontent.com/<upstream>/HEAD/<path>"`.

Rules:

- **Show the diff before writing**, for every file, including ones in `apply`.
  "Safe to take" means nobody edited it here, not that they wanted the change.
- **Never write a `conflict` file without the user having seen both versions.**
- **A failed fetch is a stop, not a skip.** Half-applying an update leaves a
  copy in a state neither version was tested in. Report which files landed and
  which did not.
- If a file needs a matching change elsewhere - a skill and its Cursor router,
  a hook and its `settings.json` entry - take both or neither.

## 4. Record what happened

After applying, regenerate the manifest so the next sync compares against where
they are now rather than where they were:

```bash
bash bin/trellis-manifest.sh --write
```

Then update `version=` in `.trellis/source` to the release just synced to, and
commit the whole thing together. A manifest committed without the files it
describes is worse than none.

If the user declined everything, change nothing - not the manifest, not the
version. Declining is not syncing, and recording it as a sync would hide those
same updates next time.
