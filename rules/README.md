# rules/

MOBA combat ruleset for Sword and Planet, implementing `docs/pulp_moba_rpg_ruleset.md`.

## Extraction contract

This directory is structured to be lifted wholesale into `addons/mikeys_game_bones/` as
the first-party addon `mikeys_game_rules_moba` **without editing a single file inside it**.
Every constraint below keeps that true and is enforced by `rules/tests/extraction_contract_test.gd`.

- **No outward references.** Nothing under `rules/` may reference `res://scripts/`,
  `res://scenes/`, or `res://resources/`. The dependency arrow points one way: the game
  depends on `rules/`, never the reverse.
- **Dependencies are Godot 4 and `addons/mikeys_game_bones/` only.** `rules/` may use
  `Actor`, `Action`, `ActionResult`, `ActionRunner`, `Authority`, `Controller`,
  `ActorBody3D`, `GameObject`. It may not use `PlayerController3D`, `PlayerBody3D`,
  `ThirdPersonCamera3D`, or `Rules`.
- **Every global `class_name` is prefixed `Moba`** — `MobaAbility`, `MobaStatBlock`,
  `MobaCombatant`. Godot has no namespaces; the registry is flat and global.
- **No ability, weapon, or enemy number is written in GDScript.** Values load from
  `rules/data/`.
- **`rules/data/generated/` is gitignored.** It holds JSON for the Python harness only;
  nothing under `rules/` ever reads it.
- **Combat math is pure.** Formulas take plain values and return plain values — no `Node`,
  no scene tree, no `get_tree()`.
