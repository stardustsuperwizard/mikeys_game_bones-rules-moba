---
applyTo: "rules/**"
---

# Ruleset module (`rules/`)

`rules/` implements the MOBA combat ruleset in `docs/pulp_moba_rpg_ruleset.md`. It is a
self-contained module with a strictly one-way dependency arrow: the game depends on
`rules/`, never the reverse. Most rules below exist to keep that true.

**Why the module stays self-contained** (revised 2026-08-30): it was originally to be lifted
wholesale into `addons/mikeys_game_bones/` as `mikeys_game_rules_moba`. #276 removes
`addons/` entirely and that destination no longer exists. The isolation is kept for a better
reason — client and server must run identical simulation, so the rules must be loadable
without dragging in scenes, input, or presentation. That is the same reason Heroes of
Newerth kept `hon_shared` separate from `hon_client` and `hon_server`, and it is what makes
#47 tractable.

`docs/rules/README.md` holds the batch roadmap and the reasoning behind these decisions.

## Boundaries

- **No outward references.** Nothing here may reference `res://scripts/`, `res://scenes/`,
  or `res://resources/`. The dependency arrow points one way: the game depends on `rules/`,
  never the reverse. Enforced by `rules/tests/extraction_contract_test.gd`.
- **Dependencies are Godot 4 and the game's own shared types only.** Use `Actor`, `Action`,
  `ActionResult`, `ActionRunner`, `Authority`, `Controller`, `ActorBody3D`. Do not use
  `PlayerController3D`, `PlayerBody3D`, `ThirdPersonCamera3D`, or `Rules`.
  `GameObject` was on this list and is deleted by #276 — nothing ever read it.
  Reference these by global `class_name`, never by `res://` path, which is what keeps the
  contract test passing wherever the files live.
- **Do not reach sideways into the game to change it.** If the ruleset appears to need a
  change in `scripts/` or `scenes/`, stop and say so in the PR rather than making it. This
  replaces the former "never modify `addons/`" rule, which #276 makes moot by deleting
  `addons/` — and which, read literally, would block #276 itself. **#276, #277, and #278 are
  explicitly authorized to change the files this rule otherwise protects.**

## Command gate

- **Every player-originated command must be gated.** A player-initiated action flows through
  `Action` → `ActionRunner.run()` → `Authority.can_perform()` before execution. Once authorized,
  the command's resolution code (inside `rules/`, within abilities, cast/channel trackers, or
  death handling) calls `MobaCombatant` mutator methods directly. The invariant: direct calls
  to `MobaCombatant` mutators never appear in `scripts/` or `rules/input/` (the game-side
  input pathway). Enforced by `rules/tests/command_mutator_contract_test.gd`.
- **Command taxonomy: one `Action` subclass, no `ActionRunner`/`Authority` edit.** Adding a
  new player-originated command means adding one new `Action` subclass with its own
  `FAILURE_*` constant block (matching `MobaAbilityAction`'s convention for failure reasons).
  It requires no edit to `scripts/action_runner.gd` or `scripts/authority.gd`, and no command
  registry, command-kind enum, or dispatch table. `ActionRunner.run()` routes every `Action`
  through `Authority.can_perform()` uniformly; each command type is a new `Action` subclass,
  not a new branch in an executor. Demonstrated by
  `rules/tests/command_taxonomy_contract_test.gd`.

## Naming

- **Every global `class_name` is prefixed `Moba`** — `MobaAbility`, `MobaCombatant`,
  `MobaFormulas`. Godot has no namespaces: `class_name` is one flat registry shared with
  every installed addon. Both original reasons are now void — this module no longer ships
  into other projects (#276), and as of 2026-08-31 the project takes no third-party addons,
  so the registry holds only this project's classes and Godot's built-ins. The prefix stays
  on a weaker but honest argument: it makes the `rules/` module boundary legible at every
  call site, and renaming ~100 classes is a large, risky, zero-value refactor. Keep by
  inertia, not by argument.
- This deliberately differs from the bare names in `scripts/` — `Actor`, `CharacterSheet`.
  **Two naming conventions in this repository is an accepted, deliberate cost.** Do not
  "fix" the inconsistency in either direction, and do not rename the existing bare-named
  classes.

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
- **Do not add third-party dependencies or addons.** Decided 2026-08-31: this project
  builds what it needs. If something looks like it wants a plugin, say so in the PR rather
  than adding one.
- Run `.github/scripts/validate-godot.sh` and report the exact command and its result. Exit
  code 127 means Godot was not on PATH — that is "could not validate", not "validated
  successfully".
