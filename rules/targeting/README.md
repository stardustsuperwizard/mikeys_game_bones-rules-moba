# Targeting System

Provides canonical ability-target resolution strategies for all targeting types.

## MobaTargeting

Core resolution strategies for each targeting type:

- `resolve_self()` — Target is the caster (always succeeds)
- `resolve_targeted()` — Target is the explicit target (single-target, range-checked inline in MobaAbilityAction)
- `resolve_channeled()` — Target is the explicit target (same as targeted; channels apply per-tick)
- `resolve_area()` — Physics shape query at caster position, within `area_radius`
- `resolve_ground()` — Physics shape query at ground point (aimed location), within `area_radius`

All multi-target strategies route through the shared `filter_valid_targets()` filter.

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
