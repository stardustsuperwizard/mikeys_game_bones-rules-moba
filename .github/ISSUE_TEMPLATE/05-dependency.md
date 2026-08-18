---
name: Dependency integration
about: Dependencies that are more operationally complicated than ordinary code features—itch.io plugins, art packs, models, audio, etc.
title: ''
labels: infrastructure, machine
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