<!--
Sword and Planet uses one issue → one pull request → one squashed commit.
See CONTRIBUTING.md and docs/AGENT_WORKFLOW.md.
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

## Agent Session Metadata

<!--
Recorded so model routing can be evaluated against outcomes over time.
Read by .github/scripts/agent-metrics.py — keep the labels exactly as written.
Leave a field blank or as "none" if it does not apply.
-->

- Implementation model: <e.g. Claude Haiku 4.5>
- Review model: <e.g. Claude Opus 5>
- Reasoning level: <default | high — drives credit consumption independently of model>
- Rework cycles: <number of FIX verdicts before PASS>
- Steering messages: <mid-session corrections sent; each one costs credits and signals under-specification>
- Session wall-clock: <e.g. 12m — rough token proxy, no per-session cost is exposed>
