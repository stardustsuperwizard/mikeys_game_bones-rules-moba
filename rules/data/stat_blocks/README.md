# Character Stat Block Definitions

Authored as `.tres` Godot Resource files in the Godot inspector.
Each stat block defines base health, mana, armor, resistance, and other core combat statistics.

`stat_allocation_policy.tres` also lives here. It is a `MobaStatAllocationPolicy`
rather than a stat block: the point pool a character build may spend on top of a
baseline, the per-stat cap, and which stats are allocatable. `MobaBuildValidator`
reads it; the pool size and cap exist only in this file, never as GDScript
literals, because they are tuning values a human is expected to revisit.
