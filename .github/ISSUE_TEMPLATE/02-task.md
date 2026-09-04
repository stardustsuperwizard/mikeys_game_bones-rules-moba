---
name: Task
about: Not every issue needs to pretend to be a “feature.”
title: '[plan] '
labels: plan, task
assignees: ''

---
## Goal

<!--
What needs to change?
Things like:
  - Update README
  - Rename workflow
  - Remove obsolete file
  - Add license header
-->
## Requirements

<!--
- ...
- ...
-->
## Acceptance Criteria

<!--
- [ ] ...
-->
## Out of Scope

<!--
- ...
-->

## Dependencies

<!--
The one place a dependency is declared in this repository. Two relationship
words and only two -- `Blocked by` and `Blocks` -- and you write whichever end
you happen to know about:

| Blocked by | #12 | Needs the effect container API |
| Blocks | #34 | #34 consumes the resolver this adds |

Add the `blocker` label to any Issue with a `Blocks` row.
`.github/workflows/issue-dependencies.yml` reads this table and creates
GitHub's native blocked-by relationship from it, which is what the control
plane orders by and what `agent:execute` refuses to run past. Write the row;
do not wire the relationship by hand.

Leave the `None` row exactly as it is when there are no dependencies.
-->

| Relationship | Issue | Why |
| --- | --- | --- |
| None | — | — |
