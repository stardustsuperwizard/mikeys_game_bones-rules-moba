---
name: Feature request
about: Suggest an idea for this project
title: ''
labels: enhancement
assignees: ''

---

## Goal

## Requirements

## Constraints

- Do not add gameplay systems.
- Do not add third-party dependencies.
- Do not create framework abstractions.
- Prefer composition over adding new base classes.
- Follow existing naming conventions.

## Acceptance Criteria

- [ ] Repository contains a valid Godot project.
- [ ] A main scene is configured.
- [ ] Godot can load the project without errors.
- [ ] No functionality beyond project initialization is introduced.

## Out of Scope

- Player character
- Input
- UI
- Networking
- Combat
- Inventory
- Assets

## Agent instructions

Inspect existing implementations before writing code.

If the requested behavior conflicts with the existing architecture,
preserve the architecture and explain the conflict in the PR rather
than introducing a workaround.

Open a PR when complete.
