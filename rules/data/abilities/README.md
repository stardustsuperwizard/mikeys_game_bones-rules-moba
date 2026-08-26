# Ability Definitions

Authored as `.tres` Godot Resource files in the Godot inspector.
Each ability resource defines damage, cooldown, resource cost, and targeting behavior.

## Content Loading

Everything in this directory is loaded as live game content by `MobaAbilityLibrary`. Every `.tres` file dropped here becomes a registered, activatable ability in a normal game load. Do not place sample or schema-reference files here; use `rules/tests/fixtures/abilities/` for fixtures and examples.

For a complete reference example exercising the full `MobaAbility` schema including `MobaCrowdControlSpec` and `MobaStatModifier` sub-resources, see `rules/tests/fixtures/abilities/sample_complete.tres`.
