---
name: Bug Report
about: Document identified bug for fixing.
title: '[plan] '
labels: plan, bug
assignees: ''

---
## Summary
<!--What is broken?-->

## Expected Behavior
<!--What should happen?-->

## Actual Behavior
<!--What happens instead?-->

## Reproduction Steps

1. ...
2. ...
3. ...
4. ...

## Reproduction Rate

<!--
- Always
- Frequently
- Intermittently
- Once / unable to reproduce reliably
-->

## Environment

- Godot version:
- Branch/commit:
- Platform:
- Relevant configuration:

## Evidence

<!--
Logs, screenshots, videos, error messages, stack traces, etc.
-->

## Suspected Scope (Optional)

<!--
Optional.

What system appears to be involved?

Do not prescribe a solution unless the implementation genuinely matters.
-->

## Constraints

- Fix the underlying defect rather than suppressing the symptom.
- Do not weaken tests to make the issue disappear.
- Avoid unrelated refactoring.

## Acceptance Criteria

- [ ] Reproduction steps no longer reproduce the defect.
- [ ] Expected behavior is restored.
- [ ] Regression test added when practical.
- [ ] Existing tests pass.
- [ ] Godot headless validation passes.

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
