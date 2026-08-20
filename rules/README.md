# rules/ — MOBA Combat Ruleset Module

This directory is the single home for the MOBA combat ruleset described in
`docs/pulp_moba_rpg_ruleset.md`. It is structured so it can be lifted wholesale
into `addons/mikeys_game_bones/` as `mikeys_game_rules_moba` without editing any
file inside it.

## Extraction Contract

Every later ruleset issue inherits these constraints:

- **No outward references.** Nothing under `rules/` may reference `res://scripts/`,
  `res://scenes/`, or `res://resources/`. The dependency arrow points one way: the
  game depends on `rules/`, never the reverse.
- **Dependencies are Godot 4 and `addons/mikeys_game_bones/` only.** `rules/` may
  use `Actor`, `Action`, `ActionResult`, `ActionRunner`, `Authority`, `Controller`,
  `ActorBody3D`, `GameObject`. It may not use `PlayerController3D`, `PlayerBody3D`,
  `ThirdPersonCamera3D`, or `Rules`.
- **Do not modify `addons/mikeys_game_bones/`.** If the ruleset appears to need a
  framework change, stop and say so in the PR.
- **`Moba` class name prefix — confirmed, not optional.** Every global `class_name`
  introduced under `rules/` is prefixed `Moba` — `MobaAbility`, `MobaStatBlock`,
  `MobaCombatant`.
- **Data, not literals.** No ability, weapon, or enemy number is written in GDScript.
  Values load from `rules/data/`.
- **Godot authors, Python consumes.** Game content is authored as `.tres`. The
  `rules/data/generated/` directory holds JSON exported for the Python balance harness
  only; it is gitignored and nothing under `rules/` ever reads it.
- **Combat math is pure.** Formulas and resolution take plain values and return plain
  values — no `Node`, no scene tree, no `get_tree()`.

The contract is machine-checked by `rules/tests/extraction_contract_test.gd`.
