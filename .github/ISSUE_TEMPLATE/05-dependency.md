---
name: Dependency integration
about: Dependencies that are more operationally complicated than ordinary code features—itch.io plugins, art packs, models, audio, etc.
title: '[plan] '
labels: plan, dependency
assignees: ''

---
## Goal

What dependency or asset needs to become available to the project?

## Dependency

**Name:**  
**Version:**  
**Source:**  
**License:**  
**Public or private:**  

## Purpose

Why does the project need this dependency?

## Required Project Location

Example:

`addons/example_plugin/`

or

`assets/characters/example/`

## Installation / Restoration

Describe how a clean development environment should obtain it.

If private:

- do not commit restricted source/assets publicly
- use approved private artifact storage
- verify integrity after retrieval

## Agent Access

Agents may:

- [ ] read source
- [ ] use public APIs
- [ ] inspect assets
- [ ] modify dependency

Default should generally be **modify: no**.

## Validation

How do we know integration succeeded?

1. Fresh environment obtains dependency.
2. Godot discovers/imports it.
3. Project loads headlessly.
4. Relevant functionality works.

## Acceptance Criteria

- [ ] Dependency version is pinned.
- [ ] Clean environment can restore it.
- [ ] License/redistribution requirements are respected.
- [ ] Agent can access required interfaces.
- [ ] Godot headless validation passes.

## Out of Scope

- Updating dependency
- Forking dependency
- Modifying vendor code
- ...

## Dependencies

<!--
Other *Issues*, not the third-party dependency this ticket is about — that one
goes under `## Dependency` above. This section is the one place an Issue-to-
Issue edge is declared in this repository. Two relationship words and only two -- `Blocked by` and `Blocks` -- and you write whichever end
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
