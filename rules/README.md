# MOBA Rules Module Extraction Contract

This module implements the complete MOBA combat ruleset specified in `docs/pulp_moba_rpg_ruleset.md`.
The entire `rules/` directory is designed to be extracted wholesale into `addons/mikeys_game_bones/`
as the first-party addon `mikeys_game_rules_moba` **without editing a single file inside it**.

## Architectural Constraints

- **No outward dependencies**: Nothing here references `res://scripts/`, `res://scenes/`, or `res://resources/`.
  The dependency arrow points one way: the game depends on `rules/`, never the reverse.
- **Limited inbound dependencies**: Code here depends only on Godot 4 and the public API of `addons/mikeys_game_bones/`.
- **Naming convention**: Every global `class_name` is prefixed with `Moba` to avoid collisions when extracted into other projects.
- **Pure, testable combat math**: All formulas live in a single module, are static, take plain values, and touch no scene tree.
- **Deterministic simulation**: Systems advance on explicit `tick(delta)` calls from their owner, enabling headless testing and Python mirroring.

## Module Organization

See each subdirectory's README for details. Key sections:
- `core/` - fundamental types and combat mechanics
- `abilities/` - ability definitions and activation pipeline
- `effects/` - status effects, buffs, debuffs, and stat modifiers
- `state/` - character state machine and interrupt handling
- `targeting/` - targeting modes and resolution
- `input/` - device-agnostic input intent
- `ai/` - threat tables and enemy behavior
- `net/` - networking and synchronization
- `ui/` - HUD and visual feedback signals
- `tools/` - development utilities and validation
- `data/` - hand-authored game content and generated exports
- `tests/` - automated contract and regression tests

## Data Formats

Three kinds of file exist here:

1. **Authored `.tres` files** - abilities, passives, weapons, loadouts, enemies, stat blocks. Godot loads these directly.
2. **Authored `.json` files** - the interrupt table, device multipliers, conformance fixtures. Committed to version control.
3. **Generated `.json` files** - Python exports of `.tres` data. Gitignored; exists only so the Python harness needs no `.tres` parser.

## Version

`MobaRules.VERSION` holds the semantic version of this module.
