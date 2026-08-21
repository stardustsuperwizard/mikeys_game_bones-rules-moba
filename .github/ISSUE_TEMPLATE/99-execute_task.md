---
name: Implementation Task
about: A bounded engineering task emitted by the planner. Not for human-authored feature requests.
title: '[impl] '
labels: implementation, machine, agent:execute
assignees: ''
---

<!--
This Issue is generated from an approved Feature implementation plan.

It MUST:
- be a direct GitHub sub-issue of the parent Feature;
- use the parent Feature's milestone when one exists;
- contain enough context to execute without access to the planner session;
- be assigned to Copilot only after planning is complete.

The implementation PR closes THIS Issue, not the parent Feature.
-->

## Plan Reference

- Plan: `docs/plans/<issue-number>-<slug>.md`
- Plan Task: <task number and task title>
- Parent Feature: #<issue-number>

## Objective

<!--
One or two sentences describing the engineering outcome.
Describe WHAT must exist after implementation, not the implementation process.
-->

## Scope

<!--
The smallest independently useful change satisfying this task.
This section is authoritative for implementation scope.
-->

## Files or Subsystems Expected to Change

<!--
These are expectations rather than permission to modify unrelated code.

- `path/to/file.gd`
- `path/to/test.gd`
-->

## Architecture Constraints

<!--
Decisions already made by the planner. The implementer must not reinterpret
or redesign these without escalating the task.
-->

- Use existing framework APIs under `addons/` rather than duplicating behavior.
- Preserve the Actor / ActorBody3D / Controller separation.
- Do not add third-party dependencies.

<!--
- <task-specific architecture constraint>
-->

## Acceptance Criteria

<!--
Every criterion should describe an observable or testable result.
-->

- [ ] <observable requirement>
- [ ] <observable requirement>
- [ ] Existing tests pass
- [ ] `.github/scripts/validate-godot.sh` passes

## Out of Scope

<!--
Explicit hard boundaries. If discovered work falls here, report it rather
than implementing it.
-->

- <explicit exclusion>

## Dependencies

<!--
Use GitHub's native blocked-by relationship for dependencies.
This section exists so the Issue remains understandable when read alone.
-->

- Blocked by: <issue number or "none">

## Implementation Agent Contract

The implementation agent MUST:

- implement only the Scope and Acceptance Criteria above;
- preserve the listed Architecture Constraints;
- avoid speculative improvements;
- avoid implementing sibling tasks;
- report discovered out-of-scope work rather than implementing it;
- run `.github/scripts/validate-godot.sh`;
- report any unsatisfied acceptance criterion.

The implementation agent MUST NOT:

- create additional GitHub Issues;
- redesign architecture;
- expand this task;
- close the parent Feature.

## Completion

The implementation pull request must include:

`Closes #<this-implementation-issue-number>`

It must not close the parent Feature unless explicitly instructed by the
planner because that pull request completes the entire Feature.
