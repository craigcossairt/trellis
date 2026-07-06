---
name: launch-check
description: Run a pre-demo/pre-launch audit of the app - test data, broken screens, missing error states, brand consistency. Use when asked to 'demo check', 'launch check', 'pre-demo audit', 'check before user interview', 'audit before demo'.
disable-model-invocation: true
---

You are running a pre-demo audit. This ensures the app is presentable for user interviews,
investor pitches, or a launch.

<!-- FILL IN: the bracketed slots below once the project has real screens and branding. -->

## Audit Steps

### 1. Test Data Cleanup

Check for and flag any test/dev artifacts that would look unprofessional:

- Search for hardcoded test emails, phone numbers, or names in the codebase
- Search for `TODO`, `FIXME`, `HACK`, `XXX` in screens/pages that are part of the demo flow
- Check for debug print/log statements in production code paths

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" <source-dir> | head -20
grep -rn "console\.log\|debugPrint\|print(" <source-dir> | head -20
```

### 2. Critical Screen Audit

Review each screen in the demo flow for polish (no layout overflow, no missing states):

<!-- FILL IN: list your critical screens/pages as checkboxes, grouped by flow -->
- [ ] Entry point (splash / landing / login)
- [ ] Core flow screen 1
- [ ] Core flow screen 2
- [ ] Settings / profile

### 3. Error State Coverage

For each critical screen, verify:
- Empty state exists and is user-friendly (not blank or an error)
- Network error handling (what happens offline?)
- Loading states (skeleton/spinner, not blank white)

### 4. Brand Consistency

<!-- FILL IN: brand colors, fonts, logo asset names -->
- Brand colors used consistently
- Correct fonts for headings and body
- Logo displays correctly
- No default framework placeholder icons visible

### 5. Static Analysis

```bash
# FILL IN: your lint/typecheck command, e.g. `npm run lint` or `flutter analyze`
```

## Output Format

Produce a report with:
- **PASS** items (confirmed good)
- **WARN** items (minor, won't break the demo but should fix)
- **FAIL** items (must fix before demo)

End with a prioritized fix list for any FAIL items.
