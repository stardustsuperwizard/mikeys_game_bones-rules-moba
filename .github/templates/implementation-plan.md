# Implementation Plan — #<issue-number> <feature title>

> Written by the planner session. This file is the handoff contract:
> implementation sessions start cold and see this document, not the
> planner's reasoning. Anything an implementer needs must be written here.

## Parent Issue

- Issue: #<issue-number>
- Design reference: <link to docs/DESIGN.md section, or "none">

## Existing Implementation Reviewed

<!-- Files and framework extension points inspected, with paths. State which
     existing APIs the work must use rather than duplicate. -->

- `<path>` — <what it does and why it matters here>

## Architecture Decisions

<!-- Decisions the implementer must NOT revisit. If a decision could not be
     made without human input, do not guess: record it under Escalations
     and stop. -->

| Decision | Rationale |
| --- | --- |
| <decision> | <why> |

## Escalations

<!-- Architectural ambiguity requiring human resolution. If this section is
     non-empty and unresolved, implementation does not start. -->

- [ ] <ambiguity, and what answer is needed to proceed>

## Task Breakdown

<!-- Minimum independently implementable tasks, in dependency order. Each
     becomes one Issue (split-session) or one delegation (single-session). -->

### Task 1 — <title>

- **Scope:** <the smallest change that satisfies the criteria>
- **Files expected to change:** `<path>`, `<path>`
- **Acceptance criteria:**
  - [ ] <observable requirement>
  - [ ] Godot headless validation passes (`.github/scripts/validate-godot.sh`)
- **Out of scope:** <explicitly prohibited for this task>
- **Depends on:** <task number, or "none">

### Task 2 — <title>

<!-- Repeat as needed. -->

## Integration Validation

<!-- What must pass once all tasks are integrated, beyond per-task criteria. -->

- [ ] `.github/scripts/validate-godot.sh` passes
- [ ] Existing tests pass
- [ ] <feature-level observable behavior>

## Human Validation Required

<!-- What cannot be verified headlessly and needs a human in the Godot editor. -->

- [ ] <or "None">
