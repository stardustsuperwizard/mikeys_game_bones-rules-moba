---
applyTo: "rules/**"
---

# Ruleset module (`rules/`)

`rules/` implements the MOBA combat ruleset in `docs/pulp_moba_rpg_ruleset.md`. It is built
to be lifted wholesale into `addons/mikeys_game_bones/` as a first-party addon named
`mikeys_game_rules_moba` **without editing a single file inside it**. Most rules below exist
to keep that true.

`docs/rules/README.md` holds the batch roadmap and the reasoning behind these decisions.

## Boundaries

- **No outward references.** Nothing here may reference `res://scripts/`, `res://scenes/`,
  or `res://resources/`. The dependency arrow points one way: the game depends on `rules/`,
  never the reverse. Enforced by `rules/tests/extraction_contract_test.gd`.
- **Dependencies are Godot 4 and `addons/mikeys_game_bones/` only.** Use `Actor`, `Action`,
  `ActionResult`, `ActionRunner`, `Authority`, `Controller`, `ActorBody3D`, `GameObject`.
  Do not use `PlayerController3D`, `PlayerBody3D`, `ThirdPersonCamera3D`, or `Rules`.
- **Never modify `addons/`.** If the ruleset appears to need a framework change, stop and
  say so in the PR rather than making it. Game rules do not belong in reusable framework
  code — see `AGENTS.md`.

## Naming

- **Every global `class_name` is prefixed `Moba`** — `MobaAbility`, `MobaCombatant`,
  `MobaFormulas`. Godot has no namespaces: `class_name` is one flat registry shared with
  every installed addon, and this module is destined to ship into other people's projects.
- This deliberately differs from the bare names in `addons/mikeys_game_bones/` and
  `scripts/` — `Actor`, `Rules`, `Door`, `CharacterSheet`. **Two naming conventions in this
  repository is an accepted, deliberate cost.** Do not "fix" the inconsistency in either
  direction, and do not rename the existing bare-named classes.

## Data

- **No ability, weapon, or enemy number is written in GDScript.** Values load from
  `rules/data/`.
- **Game content is authored as `.tres`** in the Godot inspector — abilities, passives,
  weapons, loadouts, enemies, stat blocks. GDScript loads these directly.
- **`rules/data/generated/` is gitignored and exists only for the Python harness.** Nothing
  under `rules/` ever reads it.
- Hand-edited config tables stay authored JSON and are committed: `state_transitions.json`,
  `aim_assist.json`, and `rules/data/conformance/`.

## Combat math

- **`MobaFormulas` is the only GDScript file containing a combat formula.** If another file
  needs one, it calls this. Formula duplication across the Python/GDScript split is the
  primary architectural risk of this project — see ruleset §65.
- Formulas are `static`, take plain values, return plain values, and touch no node and no
  scene tree. That is what makes them unit-testable headless and mirrorable in Python.
- **Percentages are fractions** — `0.05`, never `5.0`.
- **Randomness goes through a seedable `RandomNumberGenerator`** owned by the module, never
  the global `randf()`. Deterministic replay is required by §34 and by the conformance
  suite.
- Damage is `float` internally and is never rounded mid-pipeline. Round only for display.

## Time

- **Systems advance on an explicit `tick(delta)` from their owner, not on `_process` or
  `_physics_process`.** The balance simulation and the conformance suite require time to
  advance where the caller says it does, not where the engine says it does.

## UI (`rules/ui/`)

- **Signals in, nothing out.** The HUD observes; it never calls into the rules to change
  anything.
- **No rules logic in UI.** If the HUD needs to know whether a slot is affordable it asks
  `can_activate()`; it does not compare resource to cost itself. A formula in a UI script is
  a third copy.
- Anchors and containers, never hardcoded pixel positions — a touch HUD is coming.
- **Never assume a mouse cursor or a hover state** (§53). Gamepad and touch have neither.

## General

- Prefer typed GDScript.
- Use Godot's built-in physics. Do not write custom collision or gravity systems.
- Do not add third-party dependencies.
- Run `.github/scripts/validate-godot.sh` and report the exact command and its result. Exit
  code 127 means Godot was not on PATH — that is "could not validate", not "validated
  successfully".
