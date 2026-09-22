# DESIGN.md

Design rules your agent reads before it builds UI.

**This file asserts defaults. Override or delete any of them.** Nothing here prescribes what
your product should look like - there are no colours, no type pairings, no spacing scale,
because those are yours and a template that picked them for you would be wrong in a way that is
expensive to undo. What it does assert is the small set of habits that make a UI survive being
built fast, by an agent, over months: name your values, decide your states, and keep hierarchy
in type and space.

If you have no opinion yet, keep this file as-is and fill in the tokens as they emerge. If you
have a designer, they own everything below the first section and your job is to write their
answers down here so the agent stops guessing.

---

## The one rule the rest hang off: name the value, then use the name

A raw value in a component is the defect, not the value itself. `#3B82F6`, `14px`, `0.2s` are
each fine choices and each unfindable six weeks later. The moment the same blue appears in four
files, changing it is a search-and-replace across a codebase where one of the four is spelled
`rgb(59,130,246)`.

So: **every colour, size, spacing step, radius, weight and duration a component uses comes from
a named token.** A component that needs a value that does not exist yet gets a new token, not a
literal. Where those tokens live is stack-specific - CSS custom properties, a theme object,
design tokens JSON - and the mechanism matters far less than the rule.

This is the one habit worth enforcing from day 1, because it is nearly free at the start and
extremely expensive to retrofit. It is also what makes everything else in this file checkable:
"is this the right blue?" is a matter of taste, and "is this a literal?" is a matter of fact.

<!-- FILL IN: where tokens live in this project, e.g. `src/styles/tokens.css`, `theme.ts` -->

### Your tokens

Fill these in as they settle. Empty is honest; a guess is not.

| Token group | Where | Notes |
|---|---|---|
| Colour | <!-- FILL IN --> | |
| Type | <!-- FILL IN --> | |
| Spacing | <!-- FILL IN --> | |
| Radius / elevation | <!-- FILL IN --> | |
| Motion | <!-- FILL IN --> | |

---

## Components are the vocabulary

Once the same arrangement appears twice, it is a component and it gets a name. This is not about
reuse saving keystrokes - it is that a named component is a thing you can have an opinion about.
"The empty state of `DataTable`" is reviewable. "That bit on the reports page" is not.

An agent building without a component vocabulary will produce a plausible new variant every time,
and each one is defensible on its own. The drift is only visible in aggregate, which is exactly
when it is too late.

**Prefer an existing component over a new one, and a new component over a one-off.** If the
existing one nearly fits, change it or give it a variant. A fork named `ButtonNew` is a fork.

<!-- FILL IN: your component library or kit, e.g. shadcn/ui, a local `components/ui/` -->

---

## Every state a component can reach reserves its space before it gets there

A button whose label goes from *Save* to *Saving* must not resize itself, or the row beneath it
moves and the pointer ends up over something else. Loading, empty, error, disabled, copied and
success are **states, not afterthoughts**, and each one's footprint is decided while the
component is at rest.

The four states an agent will skip unless told: **loading, empty, error, and too-much-content.**
Ask for them by name.

## Empty, unknown and broken look different from each other

A view with no data says so. A view that could not load says something else. Neither renders as
a confident zero, because a zero someone believes is worse than an error they can act on.

No number ships without saying what it counts.

## Hierarchy comes from type and space, not chrome

Reach for size, weight and whitespace before you reach for borders, cards, badges and rules. The
tell of agent-built UI is chrome substituting for hierarchy: cards nested in cards, a pill around
every piece of metadata, a coloured band to mark a section that a heading already marked.

If two levels of hierarchy need three visual devices to tell apart, the hierarchy is the problem.

## Motion: arriving decelerates, leaving accelerates

Keep UI motion short, and give the most frequent actions the least of it. Two constraints are
about mechanism rather than taste, and both are easy to get wrong:

- **An interrupted animation resumes from where the element actually is.** Re-triggered
  mid-flight it continues; it does not restart from the beginning or queue a second run. CSS
  transitions retarget from the current computed value and keyframes do not, so this is a
  constraint on which primitive you pick.
- **Under reduced motion the information still arrives; only the trip is skipped.** Not "play it
  anyway", and not "hide the element" - the second is the common failure. Collapse the duration
  so the end state lands instantly, and never write an animation whose end state is reachable
  only by playing it.

## Show only proof that exists

Never invent testimonials, press logos, ratings, download counts, or avatar photos - not even as
placeholder. Placeholder social proof has a way of shipping. Until the real thing exists, the
honest empty state is the design.

---

## When these conflict, protect them in this order

Real screens put these rules against each other. When they collide, the higher rung wins, and an
agent should say which rung it applied rather than quietly picking.

1. **Supplied facts, legal copy, prices, units, and privacy constraints.** Never bent for
   layout. A price that does not fit gets a different layout, not a smaller unit.
2. **The existing stack and component kit.** Working inside what is already there beats a
   locally nicer thing that nothing else shares.
3. **The reader's job, and the one action the surface exists for.**
4. **Your project's authorship** - the tokens, the type, whatever makes it look like itself.
5. **A composition specific to this material**, rather than the template the category suggests.
6. **Responsive behaviour, interaction and polish** - never at the cost of a rung above.

Ask a grouped set of questions only when proceeding would change meaning, a legal or pricing
claim, privacy, or a call to action. Otherwise omit what you do not know, label it honestly, and
carry on.

---

## Tools, by where you actually are

You need less design tooling than you think, and the failure mode is collecting accounts instead
of shipping screens. Pick one rung.

**If you have never designed anything and need a screen tomorrow.** Your coding agent plus a
design skill covers in-app UI - see `docs/recommended-tooling.md`. For things that are not your
app (a landing page, a deck, a one-pager) **Claude Design** or **Google Stitch** will get you a
credible first draft from a prompt. Treat the output as a starting point you then tokenise: both
will happily hand you a wall of literal values, which is the one habit above worth protecting.

**If you know what you want and need to decide between options.** Build the options as real,
clickable prototypes and compare them side by side rather than describing them. Deciding from a
description is how a team ships the third-best idea confidently.

**If you are working with a designer, or the design is the product.** **Figma** is where that
collaboration lives. **Paper** (paper.design) is worth knowing about if you want design and code
to be one artifact rather than two that drift.

Whatever you pick, the handoff that matters is the token table above. A design that arrives as
pictures gets re-guessed on every screen.
