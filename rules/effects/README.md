# Status Effects and Modifiers

Status effects, buffs, debuffs, crowd control, and stat modifiers.
Includes stacking policies, duration tracking, and application/removal logic.

## MobaEffectContainer

`MobaEffectContainer` (`moba_effect_container.gd`) is a child `Node` of a
`MobaCombatant` that holds the combatant's active `MobaStatModifier`
instances. Entries are keyed by the identity pair `(source_ability_id,
stat)`: a second application under the same identity is resolved by the
modifier's `stacking` policy (`REFRESH`, `STACK`, `IGNORE`, or
`REPLACE_IF_STRONGER`); a different `source_ability_id` on the same stat is
an independent entry that always coexists and sums. A modifier with
`duration == 0.0` is permanent until explicitly removed. The container only
advances through `tick(delta)`, called once per frame from
`MobaCombatant.tick()` -- no `_process`, `_physics_process`, or
`SceneTreeTimer`.

Ordering is pinned: `MobaCombatant.get_stat()` applies
`(base + sum(flat)) * (1 + sum(percent))`, with flat modifiers summed before
percentage modifiers are applied, and percentages summing additively among
themselves. `get_base_stat()` keeps returning the unmodified base value.
`get_stat()` caches the computed value per stat and invalidates the whole
cache whenever the container mutates (application, refresh, stack change, or
expiry), since it sits on both the damage and movement paths.

`stack` uses a single shared duration per identity rather than one timer per
stack: every application refreshes that shared duration, including
applications made once the entry's `max_stacks` cap has already been
reached. Past the cap, magnitude stops growing but the effect stays alive as
long as it keeps being reapplied.
