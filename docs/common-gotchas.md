# Common Gotchas

Symptom → root cause → fix patterns discovered in this project. Agents: append a row after every
bug fix (see AGENTS.md § Autonomous Housekeeping). Check this table FIRST when diagnosing a bug -
the symptom may already be documented.

Keep entries terse: future sessions are the consumer and they have a limited attention budget.
Include a commit SHA and issue reference when known.

| Symptom | Root Cause | Fix | Date | Ref |
|---|---|---|---|---|
| (Example - delete me) Login form submits twice on slow connections | Submit button stays enabled while the request is in flight | Disable the button on submit; added a regression test | 2026-07-01 | #999 |
| Sync reports the whole template as deleted upstream, but only in a fresh clone | `.gitattributes` did not cover `.trellis/`, so the manifest checks out CRLF on Windows and every path carries a trailing carriage return that matches nothing | Pin `.trellis/*` to `eol=lf`; strip CR when reading the manifest. Passes when the manifest is generated locally and fails when cloned, and CI is Linux so CI never saw it | 2026-09-21 | #10 |
| A file you edited and declined comes back as "SAFE TO TAKE" on the next sync | The recording step ran `trellis-manifest.sh --write`, which hashes your whole tree, so your edits were recorded as things the template shipped | Record with `trellis-sync.sh --apply`, which rewrites only the lines it took; `--write` now refuses outside the template | 2026-09-22 | #13 |
