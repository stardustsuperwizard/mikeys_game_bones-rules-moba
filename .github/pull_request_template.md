<!--
Sword and Planet uses one issue → one pull request → one squashed commit.
See CONTRIBUTING.md and docs/AGENT_WORKFLOW.md.

A review, audit, or exploratory PR has no originating Issue. Replace the
line below with a sentence saying so, and add this marker to the body:

    <!-- no-originating-issue -->

That is what tells issue-linking.yml not to require (or infer) a closing
reference. See CLAUDE.md → "Working without an Issue".
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
