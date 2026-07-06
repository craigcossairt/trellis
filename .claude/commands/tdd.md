---
description: TDD workflow - red-green-refactor per docs/methodology/tdd.md. Use when asked to '/tdd', 'TDD workflow', 'red-green-refactor', 'test-first development', 'write the failing test first'.
---

Follow the full methodology in `docs/methodology/tdd.md` - read it now if it isn't already in
context.

Non-negotiables (details and anti-patterns in the doc):

- NEVER write implementation before its test
- ONE test at a time, vertical slices - never batch all tests then all code
- Agree the seams (public boundaries under test) with the user before writing any test
- Confirm red before implementing; confirm green before moving on; refactor only while green
- Expected values come from an independent source of truth, never recomputed the way the code does
