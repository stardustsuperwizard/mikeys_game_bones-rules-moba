# Targeting System

Provides canonical ability-target resolution strategies for all targeting types.

## MobaTargeting

Core resolution strategies for each targeting type:

- `resolve_self()` — Target is the caster (always succeeds)
- `resolve_targeted()` — Target is the explicit target (single-target, range-checked inline in MobaAbilityAction)
- `resolve_channeled()` — Target is the explicit target (same as targeted; channels apply per-tick)
- `resolve_area()` — Physics shape query at caster position, within `area_radius`
- `resolve_ground()` — Physics shape query at ground point (aimed location), within `area_radius`
- `resolve_skillshot()` — Spawns a `MobaProjectile` along `MobaCastContext.aim_direction`

All multi-target strategies route through the shared `filter_valid_targets()` filter.

`resolve_skillshot()` is the one resolver that returns no targets. A skillshot has none at
activation time: spawning the projectile *is* its resolution, and the projectile applies the
same filter to whatever it reaches later.

## MobaProjectile

An `Area3D` spawned by `resolve_skillshot()` and by nothing else. It travels along the raw
aim direction, applies the ability's effects to what it hits, and despawns on a hit, at
`max_range`, or at `lifetime_cap` — a time-based safety net independent of range.

- **`tick(delta)` is the whole implementation.** Movement, range, lifetime, collision, and
  every despawn decision live there. `_physics_process()` is a live-game driver for that
  tick and does nothing else.
- **Self-driving is disableable.** `self_driven` gates `_physics_process`, and an external
  `tick()` made while it is still on is refused loudly, so nothing can advance twice in a
  frame.
- **The travel segment is swept, not sampled.** A shapecast along the frame's motion is what
  stops `speed * delta` from skipping thin geometry.
- **Hits route through `filter_valid_targets()`.** The projectile reads no `Actor.hostile`,
  re-checks no aliveness, and re-implements no caster exclusion.
- **Combatants and world geometry differ.** A valid target takes the ability's effects, and
  the projectile despawns unless `piercing`, in which case the target enters a per-instance
  hit set and it carries on. World geometry stops it dead, applies nothing, and is never
  pierced.
- **`max_active_projectiles` is a hard cap, not a pool.** A spawn over the limit is refused
  (`resolve_skillshot()` returns null); nothing already in flight is recycled or freed to
  make room. A refused spawn is not a refunded activation — §1 charges a miss full price.

## Valid-Target Filter

The shared filter applies these checks:

- **Alive**: candidate's `MobaCombatant.is_alive()` must be true
- **Allegiance**: read `Actor.hostile` to determine friend/foe:
  - `HOSTILE` targeting hits enemies (different hostility)
  - `FRIENDLY` targeting hits allies (same hostility)
  - `ANY` targeting hits everyone
- **Caster inclusion**: exclude the caster unless `ability.affects_caster` is true
- **Stealth**: route through `_is_candidate_visible()` hook (currently always visible)

This is the **only place in the codebase that reads `Actor.hostile`** for ability targeting.

## Physics and Edge Cases

- Shape queries fail gracefully (return empty array) when no physics world exists
- Freed/invalid targets are guarded throughout
- GROUND abilities re-resolve at resolution time (after cast delay) so targets that moved out of radius during the delay are not hit
- Instant (`cast_time == 0`) abilities resolve in the activation tick through the same producer as delayed ones
