# data/

The balance source of truth. All ability, weapon, enemy, and loadout values are
authored here as .tres resources and loaded directly by GDScript at runtime.

Sub-directories:
- abilities/     — ability resource files (.tres)
- passives/      — passive ability resource files (.tres)
- weapons/       — weapon resource files (.tres)
- enemies/       — enemy definition resource files (.tres)
- loadouts/      — loadout resource files (.tres)
- stat_blocks/   — stat block resource files (.tres)
- schema/        — JSON Schema describing the exported shape for the Python harness
- generated/     — exported JSON for the Python harness (gitignored, regenerated on demand)
