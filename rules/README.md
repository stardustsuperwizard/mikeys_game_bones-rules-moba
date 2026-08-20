# rules/

MOBA combat ruleset for Sword and Planet. Designed to be extracted wholesale into
`addons/mikeys_game_bones/` as `mikeys_game_rules_moba` without editing any file here.

## Extraction contract

- **No file under `rules/` may reference `res://scripts/`, `res://scenes/`, or `res://resources/`.**
  The dependency arrow points one way: the game depends on `rules/`, never the reverse.
  Enforced by `rules/tests/extraction_contract_test.gd`.
- **Dependencies are Godot 4 and `addons/mikeys_game_bones/` only.**
  Use `Actor`, `Action`, `ActionResult`, `ActionRunner`, `Authority`, `Controller`,
  `ActorBody3D`, `GameObject`. Do not use game-layer classes.
- **Every global `class_name` is prefixed `Moba`** — e.g. `MobaRules`, `MobaAbility`,
  `MobaCombatant`. Godot has a flat `class_name` registry shared with every addon.
