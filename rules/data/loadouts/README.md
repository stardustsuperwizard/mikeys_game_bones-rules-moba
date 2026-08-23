# Combat Loadout Definitions

Authored as `.tres` Godot Resource files in the Godot inspector.
Each loadout resource extends `MobaLoadout` and specifies:
- One weapon reference
- Four action ability id slots (fixed-size, may be empty)
- One passive ability id slot (may be empty)

Slot indices are 1-based. The validation method rejects duplicate ability ids
across action slots and ensures no more than four action abilities.

## Available Loadouts

- **melee_bruiser.tres** — Melee loadout with longsword and power_strike in action slot 1.
