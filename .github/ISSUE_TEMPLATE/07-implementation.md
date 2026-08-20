---
name: Implementation Task
about: A bounded unit of work emitted by the planner session. Not for humans filing features.
title: '[impl] '
labels: implementation, agent:implement
assignees: ''

---
<!--
Opened by the planner session, one per promoted task in the implementation
plan. Create this as a direct GitHub sub-issue of the parent Feature and copy
the parent's milestone. A Parent Issue line in the body does not establish the
GitHub relationship. Assign only this sub-issue to Copilot with the model
picker set to Claude Haiku 4.5. See docs/AGENT_WORKFLOW.md.
-->

## Plan Reference

- Plan: `docs/plans/<issue-number>-<slug>.md`
- Task: <task number and title from the plan>
- Parent Feature: #<issue-number>
- Milestone: <same milestone as the parent Feature>

> This Issue must be attached as a GitHub sub-issue of the Parent Feature.
> Confirm the relationship in GitHub before assigning the implementer.

## Scope

<!-- The smallest change that satisfies the acceptance criteria. Copied from
     the plan so this Issue stands alone. -->

## Files Expected to Change

<!--
- `path/to/file.gd`
-->

## Architecture Constraints

<!-- Decisions already made in the plan. Do not revisit these. -->

- Use existing framework APIs under `addons/` rather than duplicating behavior.
- Preserve the Actor / ActorBody3D / Controller separation.
- Do not add third-party dependencies.
<!--
- <task-specific constraint>
-->

## Acceptance Criteria

- [ ] <observable requirement>
- [ ] Existing tests pass
- [ ] `.github/scripts/validate-godot.sh` passes

## Out of Scope

<!-- Explicitly prohibited for this task. Treat as a hard boundary. -->

## Depends On

<!-- A sibling implementation sub-issue number, or "none". Record the
     dependency using GitHub's blocked-by relationship as well as here. -->