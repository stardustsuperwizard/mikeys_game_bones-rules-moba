---
name: Infrastrucuture and Tooling
about: Updating the mechanisms that make the repo run
title: '[plan] '
labels: plan, infrastructure
assignees: ''

---
## Goal

<!--
What development/build/CI capability should exist afterward?
-->
## Current State

<!--
How does the system behave today?
-->
## Desired State

<!--
What should the workflow look like when complete?

Example:

Issue/PR
→ GitHub Actions
→ fresh runner
→ install Godot
→ run headless validation
→ report pass/fail
-->
## Requirements

<!--
- ...
- ...
- ...
-->

## Operational Behavior

<!--Describe important flows step-by-step.-->

### Success

<!--
1. ...
2. ...
3. ...
-->
### Failure

1. Failure reason is visible to the operator/agent.
<!--
1. ...
2. ...
3. ...
4. Failure reason is visible to the operator/agent.
-->
## Constraints

- Prefer deterministic automation over agent reasoning.
- Do not introduce persistent infrastructure unless required.
- Do not store long-lived credentials in the repository.
- Keep development setup and independent validation separate where applicable.

## Acceptance Criteria

- [ ] Failure path has been verified.
- [ ] Documentation updated where necessary.

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
plane orders by and what `agent:implementor:copilot` refuses to run past.
Write the row; do not wire the relationship by hand.

Leave the `None` row exactly as it is when there are no dependencies.
-->

| Relationship | Issue | Why |
| --- | --- | --- |
| None | — | — |
