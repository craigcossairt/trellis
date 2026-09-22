# Credits

This template is an extraction, not an invention. Most of what is good in it was
taken from somewhere, and this file is where that is recorded in one place
rather than scattered through the prose.

**If you add something borrowed, add its line here in the same commit.** The
same rule already applies to a skill and its harness router, for the same
reason: a credit recorded only in the file that happens to use the idea is a
credit nobody looking for it will find, and an idea that gets adapted and
renamed loses its parent silently.

## Ideas this template's rules came from

| What | From | Where it shows up here |
|---|---|---|
| The certainty ladder - grade a claim, name the level out loud | `blast-radius`, in Lauren Tan's **pstack** ([poteto](https://github.com/cursor/plugins/tree/main/pstack)) | `AGENTS.md` § Working Methodology |
| The skill hardening checklist | Paul Bakaus, *The Dark Arts of Skill Engineering* ([pbakaus/impeccable-talks](https://github.com/pbakaus/impeccable-talks)) | `docs/writing-your-own-skills.md`, which says so in its own Credit section |
| Six rules for prose | George Orwell, *Politics and the English Language* (1946) | `AGENTS.md` § Content Rules, optional |
| Session-management habits - rewind over correction, new task new session, compact with direction | [Thariq Shihipar](https://x.com/trq212/status/2044548257058328723) | `docs/methodology/session-management.md` |
| The "second brain" pattern - a `raw/` corpus indexed for retrieval | Ryan Wiggins' Second Brain pattern, with index/log/lint bookkeeping after Andrej Karpathy's LLM-wiki notes | `brain/` |

The rest - the push gate, branch claiming and leases, the verification gates,
the mutate-the-suite discipline, the hook adapters - came out of the production
setup this template was extracted from, and were written there before they were
written here. Several were rewritten on the way in rather than copied: a rule
with its original example stripped out usually stops saying why it exists.

## Software this template depends on or recommends

Recommending is not borrowing, but a reader deserves to know whose work they are
being pointed at, and under what terms. Full notes on each, including the ones
that will tread on this template if you install them, are in
[`docs/recommended-tooling.md`](docs/recommended-tooling.md).

| Project | Author | Used here as |
|---|---|---|
| [QMD](https://github.com/tobilu/qmd) (`@tobilu/qmd`) | tobilu | The search engine `brain/` runs on. The only external dependency of any optional feature |
| [skills](https://github.com/mattpocock/skills) | Matt Pocock | Recommended skill pack |
| [pstack](https://github.com/cursor/plugins/tree/main/pstack) | Lauren Tan | Recommended skill pack, and the source of the certainty ladder above |
| [Impeccable](https://impeccable.style/) | Paul Bakaus | Recommended, frontend design |
| [gstack](https://github.com/garrytan/gstack) and [gbrain](https://github.com/garrytan/gbrain) | Garry Tan | Recommended with warnings - both overlap things this template ships |
| [anydoc](https://github.com/firecrawl/anydoc) | Firecrawl | Recommended, documents to markdown |
| [Longshot](https://github.com/craigcossairt/Longshot) | this template's author | Recommended, screenshots. Disclosed as the author's own tool where it is listed |
| [Google Stitch](https://stitch.withgoogle.com/) | Google | Recommended, first-draft visuals for people new to design |
| [Paper](https://paper.design/) | Paper | Recommended, design and code as one artifact |
| [grill-design](https://github.com/will-ness-ai/skills) | Will Ness | This template's `/grill-design` skill is adapted from it |

## Licence

This template is MIT (see [`LICENSE`](LICENSE)). Everything above is referenced
rather than vendored - no third-party code is copied into this repository - so
each project's own licence governs it, wherever you install it from.
