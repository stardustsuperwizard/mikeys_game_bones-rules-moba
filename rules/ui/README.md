# Ruleset HUD and Visual Feedback

This directory ships with the ruleset addon. Everything here is extracted
wholesale into `addons/mikeys_game_rules_moba` alongside `rules/core/` and
`rules/abilities/`, so nothing in it may reference `res://scenes/`,
`res://scripts/`, or `res://resources/` — `rules/tests/extraction_contract_test.gd`
enforces that.

## Signals in, nothing out

These controls observe the ruleset and never call back into it. A HUD script
may connect to a `MobaCombatant` signal or call a public getter; it may never
call a mutator, spend a resource, start a cooldown, or activate an ability.

No rules logic lives here either. Readiness comes from `can_activate()`,
cooldowns from `get_cooldown_remaining()`, charges from `get_charges()`. No
formula, threshold, or cost comparison is written in a HUD script.

## Binding by assignment

Nothing here searches the scene tree for the player.

- `MobaCombatHUD.bind(combatant)` hands the HUD its combatant.
- `MobaAbilitySlot.set_ability(combatant, ability_id)` hands a slot its ability.

`bind()` is safe to call repeatedly: it disconnects the previous combatant
before connecting the new one, so a respawn cannot accumulate duplicate
connections or double updates. It also pushes the combatant's current health
and resource through the bars immediately, so the HUD is correct without
waiting for the next signal. `unbind()` drops the binding and renders the empty
state; the HUD also drops a binding whose combatant has been freed, because
`Actor.die()` calls `queue_free()`.

Health and resource are signal-driven — `health_changed` and
`resource_changed` — and are never polled per frame. The only per-frame poll in
this directory is the cooldown sweep, and it lives in the slot.

## The focused-slot tooltip seam

The HUD tracks at most one focused slot. Slots expose focus as a seam
(`MobaAbilitySlot.set_focused()` / `focus_changed`) and render no tooltip
themselves; the HUD renders the tooltip from its own focused-slot state.

Mouse hover is the only trigger wired today, and it reaches the tooltip through
that state rather than through a handler attached to the panel. A later gamepad
or touch trigger only has to call `set_focused()` — the tooltip needs no change.

## The positional slot guarantee

The four action slots are instances of `moba_ability_slot.tscn` and live as
children of one `HBoxContainer` in fixed order, slot 1 leftmost. They are never
hidden, freed, or reordered: an empty or unavailable slot renders an empty state
in place, keeping the same footprint, so slot position stays a reliable muscle
memory anchor.

The passive grouping sits beside the action row in its own container, separated
by a visible gap so the two read as distinct groups. It holds one slot-shaped
element that renders empty when no passive is selected, and cannot collapse or
shift the action slots.

Layout uses `Control` anchors and `Container` nodes throughout — no hardcoded
pixel positions — so a phone HUD and safe-area insets remain reachable without a
rewrite.

### Manual check: slot 1 stays leftmost when slot 2 goes on cooldown

1. Open `rules/ui/moba_combat_hud.tscn` and run it in the editor with a
   combatant bound, or run the game with the HUD bound to the player.
2. Note which ability is drawn in the leftmost slot of the action row.
3. Activate the slot 2 ability so it enters cooldown, and watch its sweep run.
4. Confirm, while slot 2 is sweeping, that the leftmost slot is still the same
   slot 1 ability, that four slots are still drawn, and that neither the action
   row nor the passive grouping beside it moved.

`rules/tests/hud_test.gd` covers the same guarantee headlessly.
