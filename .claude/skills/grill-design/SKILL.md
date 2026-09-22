---
name: grill-design
description: Decide a UI design by building several genuinely different working prototypes and comparing them side by side, in rounds, until the choice is locked. Use when asked to "grill the design", "design this screen", "show me options", "prototype some variants", "what should this look like", "I can't decide on a layout".
---

# Grill the design before you build it

Deciding a design from a description is how a team ships the third-best idea confidently. Nobody
can hold five layouts in their head, so whoever describes theirs most fluently wins. This
replaces the description with the thing itself: several working variants, side by side, in
rounds, until there is nothing left to decide.

Adapted from Will Ness's `grill-design`. Credit in `CREDITS.md`.

## What you produce each round

**One self-contained HTML file** with every variant inside it and a picker to switch between
them. One file, because the comparison is the product - five files in five tabs is five
impressions, not one comparison.

It must be openable by double-clicking. No build step, no dev server, no npm install. Inline the
CSS and JS. If the design needs data, inline a realistic fixture.

Three controls across the top:

- **Variant picker** - switch designs without losing your place.
- **State toggles** - at minimum loading, empty, error, and too-much-content. These are where
  designs actually differ, and the one that looks best full of tidy data is often the one that
  collapses when a title runs to three lines.
- **Width** - at least a phone width and a desktop width.

Read `DESIGN.md` before you start. It names the tokens and the priority order to resolve
conflicts with. Variants may disagree about layout; they may not disagree about the token rules.

## The variants have to be genuinely different

This is the whole discipline, and it is the step that quietly fails. Five variants that differ in
padding and border radius are one variant rendered five times, and a round spent on them teaches
nobody anything.

Make each one answer the brief with a **different idea about what matters**: a different primary
action, a different information order, a different density, a different navigation model, a
different thing on screen first. Before you build, write one line per variant saying what it
believes. If two lines could be swapped without anyone noticing, you have four variants, not
five.

Include at least one that a careful designer would push back on. The cheapest way to find the
real constraint is to cross it.

Four or five is the right number. Three is not enough spread; six is a survey nobody finishes.

## Rounds, and a verdict between each one

After each round, get a verdict per variant, not a ranking. Ranking hides the reason.

For each: **what works, what does not, and is it dead or does it continue?** Then ask what the
verdicts have in common, out loud, because the useful output of a round is usually not the
winning variant but the constraint that three of the losers violated.

The next round is narrower and deeper: take what survived, and spend the variants on the
question that is now live. Round one is "what shape is this screen"; round three is "does the
filter live in the header or the sidebar".

**Stop when a round produces no new information.** That is the signal, not a fixed number of
rounds - usually two to four. If a round changes nobody's mind, the design is decided and
continuing is procrastination with extra steps.

## Keep the same file

Rewrite the same path every round. Comparing round 3 against round 1 is a real question, and it
is answered by git, not by a folder of `prototype-v4-final-2.html`.

Say what changed since the last round in a sentence or two when you hand it over.

## Two failure modes to watch for

**CSS leaking between variants.** All variants live in one document, so a class added for
variant 4 named `.card` or `.status` restyles variants 1 through 3 and you will read it as a
design difference. Scope every class to its variant.

**Prototypes turning into the implementation.** This file exists to decide something. Once it is
decided, build the real thing in the real stack with real components - do not port the
prototype's markup across. The prototype is allowed to cheat; the product is not.

## When it is decided

Write down what was chosen **and what was rejected, with the reason**. The rejected options are
the part that stops the same debate happening again in six weeks, and they are the part everyone
forgets to record.

That goes in `docs/decision-log.md`. One entry, at whatever length the reasoning takes.
