---
name: prd-to-issues
description: Break a PRD into independently-grabbable tracker issues using tracer-bullet vertical slices. Use when asked to 'PRD to issues', 'break this PRD into tickets', 'create implementation tickets from a PRD', 'turn PRD into issues'.
---

# PRD to Issues

Break a PRD into independently-grabbable issues in the project's tracker using vertical slices
(tracer bullets).

## Process

### 1. Locate the PRD

Ask the user for the PRD issue number (or URL).

If the PRD is not already in your context window, fetch it (with comments).

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code.

### 3. Draft vertical slices

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through
ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural
decision or a design review. AFK slices can be implemented and merged without human interaction.
Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

Two kinds of work are not vertical slices, and each has its own place in the order:

- **Prefactoring goes first, as its own issue.** If a slice is only easy once some existing code
  is reshaped, make the reshaping an issue that changes no behavior, and have the slice blocked
  by it. A slice that carries its own refactor is two changes in one diff, and a reviewer can
  check neither.
- **A wide refactor is three issues: expand, migrate, contract.** When a change touches every
  caller of something (a renamed column, a new function signature), add the new form beside the
  old one, move the callers over, then remove the old form. Each step leaves the project working
  on its own, so the work can stop after any of them.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Create the issues

For each approved slice, create a tracker issue. Use the issue body template below.

Create issues in dependency order (blockers first) so you can reference real issue numbers in the
"Blocked by" field.

<issue-template>
## Parent PRD

#<prd-issue-number>

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer
implementation. Reference specific sections of the parent PRD rather than duplicating content.

## Acceptance criteria

Each criterion names what you would observe if it were NOT met.

- [ ] Criterion 1 - fails today because: <the observation, at the starting commit>
- [ ] Criterion 2 - fails today because: <...>
- [ ] Criterion 3 - fails today because: <...>

## Blocked by

- Blocked by #<issue-number> (if any)

Or "None - can start immediately" if no blockers.

## User stories addressed

Reference by number from the parent PRD:

- User story 3
- User story 7

</issue-template>

### Acceptance criteria that can fail

Before creating each issue, check every criterion against the code as it is now. **A criterion
that is already true at the starting commit proves nothing when it is true at the end.** "The
settings page works" passes before anyone touches it. "Saving a display name longer than 40
characters shows the length error; today it saves silently" can only pass once the work is done.

For each criterion, write down the observation that would show it false, and confirm that
observation holds at the starting commit: run the command, open the page, or read the code path.
If you cannot make it fail today, the criterion is either already done (drop it) or too vague to
check (rewrite it). This matters most for AFK slices, where nobody is watching the run that
declares the issue finished.

One kind stays although it passes today: a criterion that guards what the work must not break
("people who are signed in stay signed in"). Keep it, and label it *must stay true*, so that
nobody reads its passing as proof the work was done.

Do NOT close or modify the parent PRD issue.
