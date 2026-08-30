<!--
Mikey's Game Bones MOBA Rules uses one issue → one pull request → one squashed commit.
See CONTRIBUTING.md and docs/AGENT_WORKFLOW.md.

A review, audit, or exploratory PR has no originating Issue. Replace the
line below with a sentence saying so, and put the no-originating-issue
marker on the very first line of the body, above this comment. CLAUDE.md
-> "Working without an Issue" carries the exact string to paste.

It is quoted there and not here on purpose: this file's contents become
the body of every new PR, so a template that spelled the marker out would
declare every PR that left this comment in place -- including one that
merely forgot its closing reference, which is the case the check exists
to catch.
-->

Closes #<issue-number>

## Changes

<!-- Files changed and what each change does. -->

## Validation Performed

<!-- Exact commands and results. If validation could not be performed, say so
     explicitly rather than omitting it. -->

- [ ] `.github/scripts/validate-godot.sh` — <result>
- [ ] Existing tests pass — <result>
- [ ] Tests added for new behavior — <result, or why not practical>

## Acceptance Criteria

<!-- Copy from the Issue. Any unmet criterion must be called out, not hidden. -->

- [ ] <criterion>

## Discovered Out-of-Scope Work

<!-- Work found but deliberately not done.

     An executor session working an [impl] Issue lists them here and does not
     file them. The planner decides what becomes work; an executor filing its
     own discoveries is how scope creeps back in, one "while I was in there"
     Issue at a time.

     A review, audit, or other freeform session is already doing the planner's
     job -- deciding what should become work is its whole deliverable. It may
     file discovered work when asked to, and should link it here. -->

- <or "None">

## Human Validation Required

<!-- What a human must check in the Godot editor before this is trusted. -->

- [ ] <or "None">

## Review

<!-- Filled in by the reviewer session. -->

```
VERDICT:
```
