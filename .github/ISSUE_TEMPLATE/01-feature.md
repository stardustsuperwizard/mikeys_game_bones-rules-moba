---
name: Feature
about: Suggest an idea for this project
title: '[plan] '
labels: plan, enhancement
assignees: ''

---
## Primary Criteria
### Goal

<!--
 What should exist when this issue is complete? Describe the player-facing or system-facing outcome, not the implementation. 
-->
### Expected Behavior

<!-- Describe important scenarios step-by-step. -->

### Constraints

- Use existing systems and extension points where appropriate.
- Do not add third-party dependencies unless explicitly required.
- Do not modify unrelated systems.
<!--
- <feature-specific architectural constraints>
-->
### Acceptance Criteria

- [ ] Relevant automated tests exist
- [ ] Existing tests pass
- [ ] Godot headless validation passes
<!--
- [ ] Observable requirement 1
- [ ] Observable requirement 2
-->
### Out of Scope

<!--
- Player character
- Input
- UI
- Networking
- Combat
- Inventory
- Assets
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
Write the row;
do not wire the relationship by hand.

Leave the `None` row exactly as it is when there are no dependencies.
-->

| Relationship | Issue | Why |
| --- | --- | --- |
| None | — | — |

## Supporting Criteria
### Context

<!-- 
Why does this feature exist? Link any relevant design or architecture documentation.
 -->

#### Scenario: <normal/happy_path/invalid/boundary_case>

<!-- 
1. Starting condition...
2. Actor performs...
3. System responds...
4. Final state... 
-->
<!-- Copy and paste as needed to generate more scenarios. -->


### Human Validation

What, if anything, must be checked manually in Godot?
<!--
- [ ] None
- [ ] Visual appearance
- [ ] Gameplay feel
- [ ] Animation
- [ ] Other: ...
-->
## Notes

<!--
References, sketches, examples, or additional context.
-->