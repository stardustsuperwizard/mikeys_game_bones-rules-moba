<!--
Sword and Planet uses one issue → one pull request → one squashed commit.
See CONTRIBUTING.md and docs/AGENT_WORKFLOW.md.
-->

Closes #<issue-number>

## Plan Reference

- Plan: `docs/plans/<issue-number>-<slug>.md`
- Task: <task number and title, or "n/a">

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

<!-- Work found but deliberately not done. The planner decides whether these
     become Issues. Do not file them from the implementation session. -->

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
