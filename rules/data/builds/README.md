# Character Build Definitions

Authored as `.tres` Godot Resource files in the Godot inspector.
Each build resource extends `MobaCharacterBuild` and specifies:
- A character display name
- Primary and secondary Discipline (restricting which abilities are usable)
- A stat point allocation (Dictionary of stat StringName -> int points)
- A loadout (weapon + 4 action slots + 1 passive slot)

Builds are validated by `MobaBuildValidator.validate()` before submission,
ensuring Disciplines are distinct, abilities belong to the primary or secondary
Discipline, loadout is structurally valid, and stat allocation respects the
allocation policy (total pool size and per-stat cap).

## Available Builds

- **melee_bruiser_build.tres** — Warrior primary, Guardian secondary. Reuses
  `loadouts/melee_bruiser.tres` (longsword + power_strike) and spends its full
  point pool on attack damage, armor, and health.

A build references a loadout rather than replacing it. `loadouts/melee_bruiser.tres`
remains the loadout `scenes/player/player.tscn` loads directly today.

The allocation a build is checked against is `stat_blocks/stat_allocation_policy.tres`.
