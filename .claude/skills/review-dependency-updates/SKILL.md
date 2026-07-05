---
name: review-dependency-updates
description: Review outdated dependencies, security-scan each candidate bump against OSV.dev, then apply only the safe updates and PR them. Use when asked to 'review dependency updates', 'what can/should be updated', 'are we exposed to <supply-chain attack>', 'bump dependencies safely'.
---

You are running a security-conscious dependency-update review. Nothing gets bumped blindly. The
steps:

1. **List what's outdated.** Use the ecosystem's native command (`npm outdated`, `pub outdated`,
   `cargo outdated`, `pip list --outdated`, ...). Include pinned/held-back versions in the review,
   not just the auto-resolvable ones.

2. **Security-scan every candidate bump.** Use OSV.dev's `/v1/querybatch` REST API — it covers
   npm, pub, PyPI, crates.io, Go, and more, with no install required:

   ```bash
   curl -s -X POST https://api.osv.dev/v1/querybatch -d '{
     "queries": [
       {"package": {"name": "<pkg>", "ecosystem": "<npm|Pub|PyPI|crates.io>"}, "version": "<candidate-version>"}
     ]
   }'
   ```

   For an active supply-chain scare, web-search the specific compromised packages and check the
   project's lockfiles for exposure.

3. **Categorize each dep:** safe-to-bump (well-aged, no advisories), hold (major/breaking — needs
   a code change), and blocked (open CVE, or freshly published — recently-published versions are
   the supply-chain risk; don't bump onto a release that's only days old).

4. **Apply only the safe set.** Edit the manifest, run install, then run lint + the test suite to
   confirm nothing broke. Don't bundle a breaking major into a routine bump — file it separately.

5. **Handle bot PRs (Dependabot/Renovate) the same way:** review each open PR against steps 2-3,
   merge the safe ones, leave breaking/suspect ones with a comment.

6. **PR the result** with a summary table — package, old→new, why it's safe (or why deferred).
